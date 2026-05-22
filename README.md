
# kvm-backup

Small Bash script to create external qcow2 snapshots of a KVM virtual machine, copy the base disk to a backup folder, and merge the snapshot back.

## Purpose

Create consistent backups of a running VM using `virsh` external snapshots.

## Requirements

- `virsh` (libvirt) installed and configured
- Host must support qcow2 external snapshots
- Run as root or a user with permission to manage the VM and its disks

## Usage

Configure the variables in the script before running:
    - `VM` (required) — VM name
    - `DISK` (required) — disk target (example: `vda`)
    - `RETAIN_COUNT` (optional, default 14) — number of backups to keep
    - `SNAP_DIR` (optional, default "/snapshots/$VM")
    - `BACKUP_DIR` (optional, default "/backups/$VM")

### Run manually

```bash
VM=myvm DISK=vda ./vm-backup.sh
```

### Cron job

```bash
# daily at 3 AM
0 3 * * * VM=myvm DISK=vda /path/to/vm-backup.sh >> /var/log/vm-backup.log 2>&1
```

## Output

Snapshots are created under `/snapshots/<VM>` and backups are stored under `/backups/<VM>`.

## Notes

- Ensure sufficient disk space for snapshots and backups.
- Test the script on a non-production VM first to verify snapshot/merge behavior.
- The script uses `virsh domblklist` to find the original disk path — adjust if your setup differs.

## License

See the `LICENSE` file in this repository.
