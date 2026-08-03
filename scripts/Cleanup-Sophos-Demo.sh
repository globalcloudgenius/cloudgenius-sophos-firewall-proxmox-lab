#!/usr/bin/env bash
set -Eeuo pipefail

# Removes only the temporary Sophos demonstration VM and deployment staging
# files. The production VM and its disks are verified after cleanup.

DEMO_VMID="${DEMO_VMID:-110}"
PRODUCTION_VMID="${PRODUCTION_VMID:-100}"
STORAGE_PATH="${STORAGE_PATH:-}"
STAGING_ROOT="${STAGING_ROOT:-/var/lib/vz/sophos-firewall}"

[[ "$DEMO_VMID" =~ ^[0-9]+$ ]] || { echo "Invalid DEMO_VMID"; exit 1; }
[[ "$PRODUCTION_VMID" =~ ^[0-9]+$ ]] || { echo "Invalid PRODUCTION_VMID"; exit 1; }
[[ "$DEMO_VMID" != "$PRODUCTION_VMID" ]] || { echo "Demo and production VMIDs must differ"; exit 1; }

if qm status "$DEMO_VMID" >/dev/null 2>&1; then
    if qm status "$DEMO_VMID" | grep -q 'status: running'; then
        qm shutdown "$DEMO_VMID" --timeout 60
    fi

    qm status "$DEMO_VMID" | grep -q 'status: stopped' || {
        echo "VM $DEMO_VMID is not stopped. Cleanup cancelled."
        exit 1
    }

    qm destroy "$DEMO_VMID" --purge 1 --destroy-unreferenced-disks 1
fi

rm -rf "$STAGING_ROOT/packages" "$STAGING_ROOT/qcow2" "$STAGING_ROOT/logs"
find /tmp -maxdepth 1 -type f -name 'deploy-sophos-*.sh' -delete
mkdir -p "$STAGING_ROOT/packages" "$STAGING_ROOT/qcow2" "$STAGING_ROOT/logs"

echo "=== Demo VM should not appear ==="
qm list | awk -v id="$DEMO_VMID" '$1 == id'

echo "=== Demo disk directory should be empty ==="
find "$STORAGE_PATH/$DEMO_VMID" -maxdepth 1 -type f 2>/dev/null || true

echo "=== Production VM remains ==="
qm config "$PRODUCTION_VMID" | grep -E '^(name|scsi[01]):'

echo "=== Staging usage ==="
du -h --max-depth=2 "$STAGING_ROOT"

echo "Cleanup completed successfully."
