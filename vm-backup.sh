#!/bin/bash
set -euo pipefail

VM=""
DISK=""
RETAIN_COUNT=14

# Validate required config
if [[ -z "$VM" || -z "$DISK" ]]; then
    echo "ERROR: VM and DISK must be set before running this script." >&2
    exit 1
fi

DATE=$(date +"%Y-%m-%d_%H-%M")

SNAP_DIR="/snapshots/$VM"
SNAP_NAME="auto_${DATE}"
SNAPSHOT_FILE="$SNAP_DIR/${SNAP_NAME}.qcow2"

BACKUP_DIR="/backups/$VM"

LOG_FILE="/var/log/kvm_backup_${VM}.log"

# Logging helper
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2; }

# Cleanup trap
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        err "Script exited with code $exit_code. Attempting cleanup of snapshot artifacts."
        # Remove metadata only if the snapshot was actually created
        if virsh snapshot-info "$VM" "$SNAP_NAME" &>/dev/null; then
            virsh snapshot-delete "$VM" "$SNAP_NAME" --metadata || true
        fi
        rm -f "$SNAPSHOT_FILE"
    fi
}
trap cleanup EXIT

# Setup directories
mkdir -p "$SNAP_DIR" "$BACKUP_DIR"

# Capture original disk path
ORIG_DISK=$(virsh domblklist "$VM" --details \
    | awk -v disk="$DISK" '/disk/ && $3 == disk {print $4; found=1} END {if (!found) exit 1}')

if [[ -z "$ORIG_DISK" ]]; then
    err "Could not find disk '$DISK' in domblklist output for VM '$VM'."
    exit 1
fi

log "Starting backup for VM '$VM', disk '$DISK' -> '$ORIG_DISK'"

# Create snapshot
if ! virsh snapshot-create-as "$VM" "$SNAP_NAME" \
        --diskspec "$DISK,snapshot=external,file=$SNAPSHOT_FILE" \
        --disk-only --atomic --quiesce \
        --description "Scheduled snapshot"; then
    # Retry without --quiesce if the guest agent is not available
    log "WARN: --quiesce failed (guest agent may not be running). Retrying without quiesce."
    if ! virsh snapshot-create-as "$VM" "$SNAP_NAME" \
            --diskspec "$DISK,snapshot=external,file=$SNAPSHOT_FILE" \
            --disk-only --atomic \
            --description "Scheduled snapshot"; then
        err "Snapshot creation failed for VM '$VM'."
        exit 1
    fi
fi

log "Snapshot '$SNAP_NAME' created at '$SNAPSHOT_FILE'"

# Backup original disk
BACKUP_FILE="${BACKUP_DIR}/${DATE}.qcow2"
log "Copying original disk to '$BACKUP_FILE'..."
if ! qemu-img convert -f qcow2 -O qcow2 "$ORIG_DISK" "$BACKUP_FILE"; then
    err "Disk copy failed. The snapshot is still active; manual pivot/cleanup may be needed."
    exit 1
fi

# Merge snapshot delta back into base image and pivot
log "Committing and pivoting blockjob for disk '$DISK'..."
if ! virsh blockcommit "$VM" "$DISK" --active --pivot --wait --verbose; then
    err "blockcommit failed. VM '$VM' may still be running on the snapshot chain."
    err "Inspect with: virsh blockjob '$VM' '$DISK'"
    exit 1
fi

# Remove snapshot metadata and delta file
virsh snapshot-delete "$VM" "$SNAP_NAME" --metadata
rm -f "$SNAPSHOT_FILE"

log "Backup complete: $BACKUP_FILE"

# Delete files out of retain window
log "Enforcing retention: keeping $RETAIN_COUNT most recent backups."
find "$BACKUP_DIR" -maxdepth 1 -name '*.qcow2' -printf '%T@ %p\n' \
    | sort -rn \
    | awk -v keep="$RETAIN_COUNT" 'NR > keep {print $2}' \
    | xargs -r rm -f --

log "Done."