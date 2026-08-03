#requires -Version 5.1
<#
.SYNOPSIS
Safely deploys the official Sophos Firewall KVM package to Proxmox VE.

.DESCRIPTION
Uploads and validates the Sophos KVM ZIP, creates a stopped VM, imports both
official disks into a selected Proxmox storage, and connects WAN/LAN bridges.
The workflow is idempotent by VM name and rolls back only a VM created by the
current failed run. It never modifies APT repositories or host networking.

.EXAMPLE
.\Deploy-Sophos-Firewall-Proxmox.ps1 -ProxmoxHost 192.168.1.10 -Storage local-lvm

.EXAMPLE
.\Deploy-Sophos-Firewall-Proxmox.ps1 -ProxmoxHost pve01.example.local -Storage nfs-vmstore -SophosZip C:\Downloads\VI-22.0.KVM.zip -WanBridge vmbr0 -LanBridge vmbr1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$SophosZip,

    [Parameter()]
    [ValidatePattern('^/var/lib/vz/sophos-firewall/qcow2/[0-9]{8}-[0-9]{6}$')]
    [string]$ExistingRemoteImageDirectory,

    [Parameter()]
    [ValidateRange(100, 999999999)]
    [int]$VmId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*$')]
    [string]$ProxmoxHost,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$ProxmoxNode,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Storage,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$WanBridge = "vmbr0",

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$LanBridge = "vmbr1",

    [Parameter()]
    [ValidateSet('e1000', 'virtio')]
    [string]$NicModel = "e1000",

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$VmName = "SOPHOS-FW01"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install/enable the Windows OpenSSH Client and try again."
    }
}

Require-Command -Name "ssh"
Require-Command -Name "scp"

$zipItem = $null
if (-not $ExistingRemoteImageDirectory -and -not $SophosZip) {
    $downloads = Join-Path $env:USERPROFILE "Downloads"
    $candidates = @(
        Get-ChildItem -LiteralPath $downloads -File -Filter "*.zip" |
            Where-Object { $_.Name -match '(?i)(KVM|SFOS|^VI-)' } |
            Sort-Object LastWriteTime -Descending
    )

    if ($candidates.Count -eq 0) {
        throw "No likely Sophos KVM ZIP was found in '$downloads'. Run again with -SophosZip 'C:\path\file.zip'."
    }

    $SophosZip = $candidates[0].FullName
    Write-Host "Selected newest matching ZIP: $SophosZip" -ForegroundColor Yellow
}

if (-not $ExistingRemoteImageDirectory) {
    $zipItem = Get-Item -LiteralPath $SophosZip
    if ($zipItem.Extension -ne ".zip") {
        throw "SophosZip must be a .zip file."
    }
    if ($zipItem.Length -lt 1MB) {
        throw "The selected ZIP is unexpectedly small: $($zipItem.Length) bytes."
    }
}

$sshTarget = "root@$ProxmoxHost"
$runId = [Guid]::NewGuid().ToString("N")
$remoteZip = if ($ExistingRemoteImageDirectory) { "-" } else { "/tmp/sophos-$runId.zip" }
$remoteScript = "/tmp/deploy-sophos-$runId.sh"
$localRemoteScript = Join-Path ([IO.Path]::GetTempPath()) "deploy-sophos-$runId.sh"
$vmIdArgument = if ($PSBoundParameters.ContainsKey('VmId')) { $VmId.ToString() } else { "auto" }

$bash = @'
#!/usr/bin/env bash
set -Eeuo pipefail

ZIP_SOURCE="$1"
UPLOADED_ZIP="$1"
REQUESTED_VMID="$2"
VM_NAME="$3"
NODE_NAME="$4"
STORAGE="$5"
EXISTING_IMAGE_DIR="${6:-}"
WAN_BRIDGE="$7"
LAN_BRIDGE="$8"
NIC_MODEL="$9"
CHECK_ONLY="${10:-0}"
BASE_DIR="/var/lib/vz/sophos-firewall"
PACKAGE_DIR="$BASE_DIR/packages"
IMAGE_ROOT="$BASE_DIR/qcow2"
LOG_DIR="$BASE_DIR/logs"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
WORK_DIR=""
LOG_FILE="$LOG_DIR/deploy-$RUN_ID.log"
VM_CREATED=0

mkdir -p "$PACKAGE_DIR" "$IMAGE_ROOT" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

cleanup() {
    local exit_code=$?
    if [[ "$UPLOADED_ZIP" != "-" ]]; then rm -f "$UPLOADED_ZIP"; fi
    if (( exit_code != 0 )) && ! [[ "$CHECK_ONLY" == "1" && "$exit_code" == "42" ]]; then
        echo "ERROR: Deployment failed near line ${BASH_LINENO[0]}. Log: $LOG_FILE"
        if (( VM_CREATED == 1 )); then
            echo "Rolling back the incomplete VM $VMID..."
            qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
            qm destroy "$VMID" --purge 1 --destroy-unreferenced-disks 1 >/dev/null 2>&1 || true
        fi
    fi
    exit "$exit_code"
}
trap cleanup EXIT

echo "Preflight checks"
for command_name in qm pvesh pvesm qemu-img ip hostname sha256sum awk sed grep tee find cut tr mv readlink tail python3; do
    command -v "$command_name" >/dev/null || { echo "Missing command: $command_name"; exit 1; }
done

ACTUAL_NODE="$(hostname)"
if [[ -n "$NODE_NAME" && "$ACTUAL_NODE" != "$NODE_NAME" ]]; then
    echo "Connected to node '$ACTUAL_NODE', but '$NODE_NAME' was expected."
    exit 1
fi
NODE_NAME="$ACTUAL_NODE"

ip link show "$WAN_BRIDGE" >/dev/null 2>&1 || { echo "Bridge $WAN_BRIDGE does not exist."; exit 1; }
ip link show "$LAN_BRIDGE" >/dev/null 2>&1 || { echo "Bridge $LAN_BRIDGE does not exist."; exit 1; }

pvesm status --storage "$STORAGE" 2>/dev/null | grep -Eq "^${STORAGE}[[:space:]].*[[:space:]]active[[:space:]]" || {
    echo "Storage '$STORAGE' is not active on this node."
    pvesm status --storage "$STORAGE" || true
    exit 1
}
STORAGE_CONTENT="$(
    pvesh get "/storage/$STORAGE" --output-format json 2>/dev/null |
        python3 -c 'import json,sys; print(json.load(sys.stdin).get("content", ""))'
)"
[[ ",$STORAGE_CONTENT," == *,images,* ]] || {
    echo "Storage '$STORAGE' is active but is not configured for VM disk images."
    echo "Configured content types: ${STORAGE_CONTENT:-none}"
    echo "Choose a storage whose Content includes 'Disk image'."
    exit 1
}

validate_vm_config() {
    local check_vmid="$1"
    local config
    config="$(qm config "$check_vmid")"
    grep -q '^scsi0:' <<<"$config" || { echo "scsi0 validation failed."; return 1; }
    grep -q '^scsi1:' <<<"$config" || { echo "scsi1 validation failed."; return 1; }
    grep -Eq "^net0: ${NIC_MODEL}=.*bridge=${LAN_BRIDGE}" <<<"$config" || { echo "Sophos Port1/LAN NIC validation failed."; return 1; }
    grep -Eq "^net1: ${NIC_MODEL}=.*bridge=${WAN_BRIDGE}" <<<"$config" || { echo "Sophos Port2/WAN NIC validation failed."; return 1; }
    grep -q '^boot: order=scsi0' <<<"$config" || { echo "Boot-order validation failed."; return 1; }
    grep -q '^agent: 0' <<<"$config" || { echo "Guest Agent validation failed."; return 1; }
}

mapfile -t existing_records < <(
    pvesh get /cluster/resources --type vm --output-format json |
        python3 -c 'import json,sys; name=sys.argv[1]; [print("{}|{}".format(x.get("vmid"), x.get("node", ""))) for x in json.load(sys.stdin) if x.get("name") == name]' "$VM_NAME"
)
if (( ${#existing_records[@]} > 1 )); then
    echo "More than one VM is named '$VM_NAME'; refusing to guess."
    exit 1
elif (( ${#existing_records[@]} == 1 )); then
    EXISTING_VMID="${existing_records[0]%%|*}"
    EXISTING_NODE="${existing_records[0]#*|}"
    [[ "$EXISTING_NODE" == "$NODE_NAME" ]] || {
        echo "VM '$VM_NAME' already exists on node '$EXISTING_NODE' as VMID $EXISTING_VMID. No changes made."
        exit 1
    }
    validate_vm_config "$EXISTING_VMID" || {
        echo "VM '$VM_NAME' exists as VMID $EXISTING_VMID, but its configuration is incomplete or different. No changes made."
        exit 1
    }
    echo "VM '$VM_NAME' already exists as VMID $EXISTING_VMID and passed validation."
    echo "Idempotent exit: no upload, extraction, disk import, or VM change was performed."
    qm config "$EXISTING_VMID"
    exit 0
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
    echo "No existing VM named '$VM_NAME' was found; deployment is required."
    exit 42
fi

if [[ "$REQUESTED_VMID" == "auto" ]]; then
    VMID="$(pvesh get /cluster/nextid --output-format json | tr -d '"[:space:]')"
else
    VMID="$REQUESTED_VMID"
fi
[[ "$VMID" =~ ^[0-9]+$ ]] || { echo "Invalid VMID returned: $VMID"; exit 1; }
qm status "$VMID" >/dev/null 2>&1 && { echo "VMID $VMID already exists."; exit 1; }

if [[ -n "$EXISTING_IMAGE_DIR" ]]; then
    WORK_DIR="$(readlink -f "$EXISTING_IMAGE_DIR")"
    [[ "$WORK_DIR" == "$IMAGE_ROOT"/* && -d "$WORK_DIR" ]] || {
        echo "Existing image directory is invalid or outside $IMAGE_ROOT: $EXISTING_IMAGE_DIR"
        exit 1
    }
    echo "Reusing extracted images from $WORK_DIR"
else
    [[ -s "$ZIP_SOURCE" ]] || { echo "Uploaded ZIP is missing or empty."; exit 1; }
    WORK_DIR="$IMAGE_ROOT/$RUN_ID"
    mkdir -p "$WORK_DIR"
    PACKAGE_FILE="$PACKAGE_DIR/$(basename "$ZIP_SOURCE" .zip)-$RUN_ID.zip"
    mv "$ZIP_SOURCE" "$PACKAGE_FILE"
    ZIP_SOURCE="$PACKAGE_FILE"
    sha256sum "$PACKAGE_FILE" | tee "$PACKAGE_FILE.sha256"
    python3 -m zipfile -t "$PACKAGE_FILE"
    python3 -m zipfile -e "$PACKAGE_FILE" "$WORK_DIR"
fi

mapfile -t primary_matches < <(find "$WORK_DIR" -type f -iname 'PRIMARY-DISK.qcow2')
mapfile -t auxiliary_matches < <(find "$WORK_DIR" -type f -iname 'AUXILIARY-DISK.qcow2')
(( ${#primary_matches[@]} == 1 )) || { echo "Expected exactly one PRIMARY-DISK.qcow2; found ${#primary_matches[@]}."; exit 1; }
(( ${#auxiliary_matches[@]} == 1 )) || { echo "Expected exactly one AUXILIARY-DISK.qcow2; found ${#auxiliary_matches[@]}."; exit 1; }
PRIMARY_IMAGE="${primary_matches[0]}"
AUXILIARY_IMAGE="${auxiliary_matches[0]}"

for image in "$PRIMARY_IMAGE" "$AUXILIARY_IMAGE"; do
    [[ -s "$image" ]] || { echo "QCOW2 image is empty: $image"; exit 1; }
    [[ "$(qemu-img info --output=json "$image" | grep -o '"format"[^,]*' | tail -n1 | cut -d'"' -f4)" == "qcow2" ]] || {
        echo "Image is not QCOW2: $image"
        exit 1
    }
    qemu-img check "$image"
done

echo "Creating VM $VMID ($VM_NAME)"
qm create "$VMID" \
    --name "$VM_NAME" \
    --description "Sophos Firewall Home - automated KVM/QCOW2 deployment" \
    --ostype l26 \
    --bios seabios \
    --machine pc \
    --cpu host \
    --sockets 1 \
    --cores 4 \
    --memory 6144 \
    --balloon 0 \
    --scsihw virtio-scsi-single \
    --agent 0 \
    --onboot 0 \
    --net0 "${NIC_MODEL},bridge=${LAN_BRIDGE},firewall=0" \
    --net1 "${NIC_MODEL},bridge=${WAN_BRIDGE},firewall=0"
VM_CREATED=1

echo "Importing primary disk into $STORAGE"
qm importdisk "$VMID" "$PRIMARY_IMAGE" "$STORAGE"
PRIMARY_VOL="$(qm config "$VMID" | awk -F': ' '$1 ~ /^unused[0-9]+$/ {split($2,a,","); print a[1]; exit}')"
[[ -n "$PRIMARY_VOL" ]] || { echo "Primary imported volume was not found."; exit 1; }
qm set "$VMID" --scsi0 "$PRIMARY_VOL"

echo "Importing auxiliary disk into $STORAGE"
qm importdisk "$VMID" "$AUXILIARY_IMAGE" "$STORAGE"
AUXILIARY_VOL="$(qm config "$VMID" | awk -F': ' '$1 ~ /^unused[0-9]+$/ {split($2,a,","); print a[1]; exit}')"
[[ -n "$AUXILIARY_VOL" ]] || { echo "Auxiliary imported volume was not found."; exit 1; }
qm set "$VMID" --scsi1 "$AUXILIARY_VOL"
qm set "$VMID" --boot "order=scsi0"

validate_vm_config "$VMID"
[[ "$(qm status "$VMID" | awk '{print $2}')" == "stopped" ]] || { echo "VM is unexpectedly running."; exit 1; }

VM_CREATED=0
echo
echo "SUCCESS: Sophos VM created and validated."
echo "VMID: $VMID"
echo "Name: $VM_NAME"
echo "Node: $NODE_NAME"
echo "Runtime storage: $STORAGE"
echo "Source images: $WORK_DIR"
echo "Deployment log: $LOG_FILE"
echo "State: STOPPED (review before first boot)"
echo
qm config "$VMID"
'@

try {
    # UTF-8 without BOM and LF line endings are required for Bash on Proxmox.
    $normalizedBash = $bash -replace "`r`n", "`n"
    [IO.File]::WriteAllText($localRemoteScript, $normalizedBash, (New-Object Text.UTF8Encoding($false)))

    Write-Step "Testing SSH access to $sshTarget"
    & ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $sshTarget "true"
    if ($LASTEXITCODE -ne 0) { throw "SSH connectivity test failed." }

    Write-Step "Uploading the small deployment helper"
    & scp -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -- $localRemoteScript "${sshTarget}:$remoteScript"
    if ($LASTEXITCODE -ne 0) { throw "Deployment helper upload failed." }

    Write-Step "Checking for an already-completed deployment"
    $checkCommand = "chmod 700 '$remoteScript' && bash '$remoteScript' '-' '$vmIdArgument' '$VmName' '$ProxmoxNode' '$Storage' '' '$WanBridge' '$LanBridge' '$NicModel' '1'"
    & ssh -t -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $sshTarget $checkCommand
    $checkExitCode = $LASTEXITCODE
    if ($checkExitCode -eq 0) {
        Write-Host "`nExisting Sophos VM passed validation. Nothing was uploaded or changed." -ForegroundColor Green
        return
    }
    if ($checkExitCode -ne 42) {
        throw "Existing-deployment precheck failed. Review the error shown above."
    }

    if (-not $ExistingRemoteImageDirectory) {
        Write-Step "Uploading Sophos KVM ZIP"
        & scp -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -- $zipItem.FullName "${sshTarget}:$remoteZip"
        if ($LASTEXITCODE -ne 0) { throw "Sophos ZIP upload failed." }
    }

    Write-Step "Running validated Sophos deployment on $ProxmoxHost"
    $remoteCommand = "chmod 700 '$remoteScript' && bash '$remoteScript' '$remoteZip' '$vmIdArgument' '$VmName' '$ProxmoxNode' '$Storage' '$ExistingRemoteImageDirectory' '$WanBridge' '$LanBridge' '$NicModel' '0'"
    & ssh -t -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $sshTarget $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Remote Sophos deployment failed. Review the error shown above." }

    Write-Host "`nDeployment completed. The Sophos VM is intentionally powered off." -ForegroundColor Green
    Write-Host "Review its Hardware tab in Proxmox before clicking Start." -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $localRemoteScript -Force -ErrorAction SilentlyContinue
}
