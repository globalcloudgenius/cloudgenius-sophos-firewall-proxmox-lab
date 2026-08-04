#requires -Version 5.1
<#
.SYNOPSIS
Deploys and starts a Sophos Firewall Home Edition ISO VM on Proxmox VE.

.DESCRIPTION
Finds the newest SW-*.iso in the current user's Downloads directory (or uses
-IsoFile), validates the ISO, uploads it to an ISO-capable Proxmox storage,
creates a separate VM with Home Edition-compatible limits, attaches LAN/WAN
NICs, mounts the ISO, and starts the VM.

The script never changes Proxmox host networking and never deletes an existing
VM. If the requested VM name or VMID already exists, it stops safely.

.EXAMPLE
.\Deploy-Sophos-Home-Firewall-Proxmox.ps1 `
  -ProxmoxHost 192.0.2.10 `
  -ProxmoxNode pve01 `
  -DiskStorage local-lvm `
  -IsoStorage local `
  -WanBridge vmbr0 `
  -LanBridge vmbr1

.EXAMPLE
.\Deploy-Sophos-Home-Firewall-Proxmox.ps1 `
  -ProxmoxHost 192.0.2.10 `
  -DiskStorage local-lvm `
  -IsoFile "$env:USERPROFILE\Downloads\SW-22.0.1_MR-1-490.iso"
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IsoFile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*$')]
    [string]$ProxmoxHost,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$ProxmoxNode,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$DiskStorage,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$IsoStorage = 'local',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$WanBridge = 'vmbr0',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$LanBridge = 'vmbr1',

    [Parameter()]
    [ValidateSet('e1000', 'virtio')]
    [string]$NicModel = 'e1000',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$VmName = 'SOPHOS-HOME-FW01',

    [Parameter()]
    [ValidateRange(100, 999999999)]
    [int]$VmId,

    [Parameter()]
    [ValidateRange(32, 2048)]
    [int]$DiskSizeGB = 80,

    [Parameter()]
    [ValidateRange(2, 4)]
    [int]$CpuCores = 4,

    [Parameter()]
    [ValidateRange(4096, 6144)]
    [int]$MemoryMB = 6144
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Enable the Windows OpenSSH Client and retry."
    }
}

Require-Command -Name ssh
Require-Command -Name scp

if (-not $IsoFile) {
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $candidates = @(
        Get-ChildItem -LiteralPath $downloads -File -Filter 'SW-*.iso' |
            Sort-Object LastWriteTime -Descending
    )
    if ($candidates.Count -eq 0) {
        throw "No Sophos Home software ISO matching 'SW-*.iso' was found in '$downloads'. Use -IsoFile with the full path."
    }
    $IsoFile = $candidates[0].FullName
    Write-Host "Selected newest Sophos software ISO: $IsoFile" -ForegroundColor Yellow
}

$isoItem = Get-Item -LiteralPath $IsoFile
if ($isoItem.Extension -ine '.iso') {
    throw 'IsoFile must be an .iso file.'
}
if ($isoItem.Name -notmatch '(?i)^SW-[A-Za-z0-9._-]+\.iso$') {
    throw "'$($isoItem.Name)' does not look like the Sophos Software/Home Edition ISO. Expected a filename beginning with 'SW-'."
}
if ($isoItem.Length -lt 100MB) {
    throw "The ISO is unexpectedly small ($($isoItem.Length) bytes). Download it again before deployment."
}

$sshTarget = "root@$ProxmoxHost"
$runId = [Guid]::NewGuid().ToString('N')
$remoteIso = "/tmp/sophos-home-$runId.iso"
$remoteScript = "/tmp/deploy-sophos-home-$runId.sh"
$localScript = Join-Path ([IO.Path]::GetTempPath()) "deploy-sophos-home-$runId.sh"
$vmIdArgument = if ($PSBoundParameters.ContainsKey('VmId')) { $VmId.ToString() } else { 'auto' }

$bash = @'
#!/usr/bin/env bash
set -Eeuo pipefail

UPLOADED_ISO="$1"
ISO_NAME="$2"
EXPECTED_SHA256="$3"
REQUESTED_VMID="$4"
VM_NAME="$5"
EXPECTED_NODE="$6"
DISK_STORAGE="$7"
ISO_STORAGE="$8"
WAN_BRIDGE="$9"
LAN_BRIDGE="${10}"
NIC_MODEL="${11}"
DISK_SIZE_GB="${12}"
CPU_CORES="${13}"
MEMORY_MB="${14}"
VM_CREATED=0
FINAL_ISO=""

cleanup() {
    local exit_code=$?
    rm -f "$UPLOADED_ISO"
    if (( exit_code != 0 )); then
        echo "ERROR: Deployment failed near line ${BASH_LINENO[0]}."
        if (( VM_CREATED == 1 )); then
            echo "Removing only the incomplete VM created by this run: $VMID"
            qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
            qm destroy "$VMID" --purge 1 --destroy-unreferenced-disks 1 >/dev/null 2>&1 || true
        fi
    fi
    exit "$exit_code"
}
trap cleanup EXIT

echo 'Running Proxmox preflight checks'
for command_name in qm pvesh pvesm ip hostname sha256sum python3 install mv rm grep awk tr chmod sleep; do
    command -v "$command_name" >/dev/null || { echo "Missing command: $command_name"; exit 1; }
done

ACTUAL_NODE="$(hostname)"
if [[ -n "$EXPECTED_NODE" && "$ACTUAL_NODE" != "$EXPECTED_NODE" ]]; then
    echo "Connected to node '$ACTUAL_NODE', but '$EXPECTED_NODE' was requested."
    exit 1
fi

ip link show "$WAN_BRIDGE" >/dev/null 2>&1 || { echo "WAN bridge '$WAN_BRIDGE' does not exist."; exit 1; }
ip link show "$LAN_BRIDGE" >/dev/null 2>&1 || { echo "LAN bridge '$LAN_BRIDGE' does not exist."; exit 1; }
[[ "$WAN_BRIDGE" != "$LAN_BRIDGE" ]] || { echo 'WAN and LAN bridges must be different.'; exit 1; }

storage_json() {
    pvesh get "/storage/$1" --output-format json
}

DISK_CONTENT="$(storage_json "$DISK_STORAGE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("content", ""))')"
[[ ",$DISK_CONTENT," == *,images,* ]] || {
    echo "Storage '$DISK_STORAGE' does not allow VM disk images. Content: ${DISK_CONTENT:-none}"
    exit 1
}
pvesm status --storage "$DISK_STORAGE" | grep -Eq "^${DISK_STORAGE}[[:space:]].*[[:space:]]active[[:space:]]" || {
    echo "Disk storage '$DISK_STORAGE' is not active."
    exit 1
}

ISO_JSON="$(storage_json "$ISO_STORAGE")"
ISO_CONTENT="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("content", ""))' <<<"$ISO_JSON")"
ISO_PATH="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("path", ""))' <<<"$ISO_JSON")"
[[ ",$ISO_CONTENT," == *,iso,* ]] || {
    echo "Storage '$ISO_STORAGE' does not allow ISO images. Content: ${ISO_CONTENT:-none}"
    exit 1
}
[[ -n "$ISO_PATH" && "$ISO_PATH" == /* ]] || {
    echo "ISO storage '$ISO_STORAGE' has no directly accessible filesystem path. Use a directory, NFS, or CIFS storage with ISO content enabled."
    exit 1
}
pvesm status --storage "$ISO_STORAGE" | grep -Eq "^${ISO_STORAGE}[[:space:]].*[[:space:]]active[[:space:]]" || {
    echo "ISO storage '$ISO_STORAGE' is not active."
    exit 1
}

mapfile -t NAME_MATCHES < <(
    pvesh get /cluster/resources --type vm --output-format json |
        python3 -c 'import json,sys; n=sys.argv[1]; [print(x.get("vmid")) for x in json.load(sys.stdin) if x.get("name") == n]' "$VM_NAME"
)
if (( ${#NAME_MATCHES[@]} > 0 )); then
    echo "A VM named '$VM_NAME' already exists (VMID ${NAME_MATCHES[0]}). No changes were made."
    exit 1
fi

if [[ "$REQUESTED_VMID" == 'auto' ]]; then
    VMID="$(pvesh get /cluster/nextid --output-format json | tr -d '"[:space:]')"
else
    VMID="$REQUESTED_VMID"
fi
[[ "$VMID" =~ ^[0-9]+$ ]] || { echo "Invalid VMID: $VMID"; exit 1; }
qm status "$VMID" >/dev/null 2>&1 && { echo "VMID $VMID already exists. No changes were made."; exit 1; }

ACTUAL_SHA256="$(sha256sum "$UPLOADED_ISO" | awk '{print $1}')"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || {
    echo 'Uploaded ISO checksum does not match the local file.'
    exit 1
}

ISO_DIRECTORY="$ISO_PATH/template/iso"
install -d -m 0755 "$ISO_DIRECTORY"
FINAL_ISO="$ISO_DIRECTORY/$ISO_NAME"
if [[ -f "$FINAL_ISO" ]]; then
    EXISTING_SHA256="$(sha256sum "$FINAL_ISO" | awk '{print $1}')"
    if [[ "$EXISTING_SHA256" == "$EXPECTED_SHA256" ]]; then
        echo "Identical ISO already exists at $FINAL_ISO; reusing it."
        rm -f "$UPLOADED_ISO"
    else
        echo "An ISO named '$ISO_NAME' already exists with different contents. Refusing to overwrite it."
        exit 1
    fi
else
    mv "$UPLOADED_ISO" "$FINAL_ISO"
    chmod 0644 "$FINAL_ISO"
fi

ISO_VOLUME="$ISO_STORAGE:iso/$ISO_NAME"
echo "Creating Sophos Home VM $VMID ($VM_NAME)"
qm create "$VMID" \
    --name "$VM_NAME" \
    --description 'Sophos Firewall Home Edition - software ISO installation' \
    --ostype l26 \
    --bios seabios \
    --machine pc \
    --cpu host \
    --sockets 1 \
    --cores "$CPU_CORES" \
    --memory "$MEMORY_MB" \
    --balloon 0 \
    --agent 0 \
    --onboot 1 \
    --startup order=20,up=60,down=60 \
    --scsihw virtio-scsi-single \
    --scsi0 "$DISK_STORAGE:$DISK_SIZE_GB,discard=on,iothread=1,ssd=1" \
    --ide2 "$ISO_VOLUME,media=cdrom" \
    --net0 "$NIC_MODEL,bridge=$LAN_BRIDGE,firewall=0" \
    --net1 "$NIC_MODEL,bridge=$WAN_BRIDGE,firewall=0" \
    --boot "order=ide2;scsi0"
VM_CREATED=1

CONFIG="$(qm config "$VMID")"
grep -q "^scsi0: $DISK_STORAGE:" <<<"$CONFIG" || { echo 'System disk validation failed.'; exit 1; }
grep -q "^ide2: $ISO_VOLUME" <<<"$CONFIG" || { echo 'ISO attachment validation failed.'; exit 1; }
grep -Eq "^net0: ${NIC_MODEL}=.*bridge=${LAN_BRIDGE}" <<<"$CONFIG" || { echo 'Port1/LAN validation failed.'; exit 1; }
grep -Eq "^net1: ${NIC_MODEL}=.*bridge=${WAN_BRIDGE}" <<<"$CONFIG" || { echo 'Port2/WAN validation failed.'; exit 1; }

qm start "$VMID"
sleep 2
qm status "$VMID" | grep -q 'status: running' || { echo 'VM did not enter the running state.'; exit 1; }
VM_CREATED=0

echo
echo "SUCCESS: Sophos Home VM $VMID is running on node $ACTUAL_NODE."
echo "Port1/LAN -> $LAN_BRIDGE"
echo "Port2/WAN -> $WAN_BRIDGE"
echo "Mounted ISO -> $ISO_VOLUME"
echo 'Open the Proxmox console and complete the interactive Sophos installation.'
qm config "$VMID"
'@

try {
    Write-Step 'Calculating the local ISO SHA-256 checksum'
    $localHash = (Get-FileHash -LiteralPath $isoItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "SHA-256: $localHash"

    [IO.File]::WriteAllText($localScript, ($bash -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))

    Write-Step "Uploading $($isoItem.Name) to $ProxmoxHost"
    & scp -- $isoItem.FullName "${sshTarget}:$remoteIso"
    if ($LASTEXITCODE -ne 0) { throw "ISO upload failed with exit code $LASTEXITCODE." }

    Write-Step 'Uploading the validated deployment helper'
    & scp -- $localScript "${sshTarget}:$remoteScript"
    if ($LASTEXITCODE -ne 0) { throw "Helper upload failed with exit code $LASTEXITCODE." }

    $arguments = @(
        $remoteIso,
        $isoItem.Name,
        $localHash,
        $vmIdArgument,
        $VmName,
        $ProxmoxNode,
        $DiskStorage,
        $IsoStorage,
        $WanBridge,
        $LanBridge,
        $NicModel,
        $DiskSizeGB.ToString(),
        $CpuCores.ToString(),
        $MemoryMB.ToString()
    )
    $quotedArguments = $arguments | ForEach-Object { "'$_'" }
    $remoteCommand = "chmod 700 '$remoteScript' && '$remoteScript' $($quotedArguments -join ' ')"

    Write-Step 'Creating and starting the Sophos Home Edition VM'
    & ssh -t $sshTarget $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Remote deployment failed with exit code $LASTEXITCODE." }

    Write-Host "`nDeployment completed successfully." -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $localScript -Force -ErrorAction SilentlyContinue
    & ssh $sshTarget "rm -f '$remoteScript' '$remoteIso'" 2>$null | Out-Null
}
