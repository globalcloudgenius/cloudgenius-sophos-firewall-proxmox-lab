#!/usr/bin/env bash
set -Eeuo pipefail

# Explicitly removes one disposable Sophos Home demo VM.
# It refuses the validated production VMID/name and performs no broad file deletion.

DEMO_VMID="${DEMO_VMID:-}"
EXPECTED_DEMO_NAME="${EXPECTED_DEMO_NAME:-SOPHOS-HOME-DEMO}"
PROTECTED_VMID="${PROTECTED_VMID:-101}"
PROTECTED_NAME="${PROTECTED_NAME:-SOPHOS-HOME-FW01}"

[[ -n "$DEMO_VMID" ]] || {
    echo "Set DEMO_VMID explicitly, for example: DEMO_VMID=110 $0"
    exit 2
}
[[ "$DEMO_VMID" =~ ^[0-9]+$ ]] || { echo "Invalid DEMO_VMID."; exit 2; }
[[ "$PROTECTED_VMID" =~ ^[0-9]+$ ]] || { echo "Invalid PROTECTED_VMID."; exit 2; }
[[ "$EXPECTED_DEMO_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "Invalid EXPECTED_DEMO_NAME."; exit 2; }
[[ "$DEMO_VMID" != "$PROTECTED_VMID" ]] || { echo "Refusing to remove protected VMID $PROTECTED_VMID."; exit 1; }

qm status "$DEMO_VMID" >/dev/null 2>&1 || {
    echo "VMID $DEMO_VMID does not exist. Nothing changed."
    exit 0
}

CONFIG="$(qm config "$DEMO_VMID")"
ACTUAL_NAME="$(awk -F': ' '$1 == "name" { print $2 }' <<<"$CONFIG")"
[[ "$ACTUAL_NAME" == "$EXPECTED_DEMO_NAME" ]] || {
    echo "VMID $DEMO_VMID is named '$ACTUAL_NAME', not '$EXPECTED_DEMO_NAME'. Refusing to delete it."
    exit 1
}
[[ "$ACTUAL_NAME" != "$PROTECTED_NAME" ]] || {
    echo "Refusing to remove protected VM '$PROTECTED_NAME'."
    exit 1
}

echo "Target verified: VMID $DEMO_VMID ($ACTUAL_NAME)"
read -r -p "Type the VMID to permanently destroy this demo VM and its disks: " CONFIRM_VMID
[[ "$CONFIRM_VMID" == "$DEMO_VMID" ]] || { echo "Confirmation did not match. Cancelled."; exit 1; }

if qm status "$DEMO_VMID" | grep -q 'status: running'; then
    qm shutdown "$DEMO_VMID" --timeout 60
fi
qm status "$DEMO_VMID" | grep -q 'status: stopped' || {
    echo "VM did not stop. Cleanup cancelled."
    exit 1
}

qm destroy "$DEMO_VMID" --purge 1 --destroy-unreferenced-disks 1
qm status "$DEMO_VMID" >/dev/null 2>&1 && {
    echo "VM still exists after destroy."
    exit 1
}

echo "Demo VM $DEMO_VMID was removed. This operation is not recoverable unless a backup exists."
