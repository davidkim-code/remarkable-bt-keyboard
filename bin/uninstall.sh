#!/bin/sh
# uninstall.sh — revert what install-rootfs-hooks.sh did.
#
# Default: stop and remove the systemd units, restore /etc/pm/sleep.wakesrc
#          for the current uptime, remove the disable flag and the scripts
#          under /home/root/bin/. KEEPS BlueZ pairing data so re-installing
#          later doesn't force you to re-pair.
#
# --purge: above, plus forget every paired keyboard.
#
# Usage:
#   /home/root/bin/uninstall.sh
#   /home/root/bin/uninstall.sh --purge

set -eu

PURGE=0
case "${1:-}" in
    --purge) PURGE=1 ;;
    -h|--help)
        sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    "") ;;
    *)
        echo "Unknown argument: $1" >&2
        echo "Usage: $0 [--purge]" >&2
        exit 2
        ;;
esac

log() { printf '[uninstall] %s\n' "$*"; }

log "stopping services"
for s in bt-keyboard-watchdog bt-no-suspend-wake btnxpuart-load; do
    systemctl stop "$s.service" 2>/dev/null || true
done

log "remounting / rw"
mount -o remount,rw /

log "removing systemd units and symlinks"
rm -f /lib/systemd/system/btnxpuart-load.service \
      /lib/systemd/system/bt-no-suspend-wake.service \
      /lib/systemd/system/bt-keyboard-watchdog.service \
      /lib/systemd/system/sysinit.target.wants/btnxpuart-load.service \
      /lib/systemd/system/sysinit.target.wants/bt-no-suspend-wake.service \
      /lib/systemd/system/multi-user.target.wants/bt-keyboard-watchdog.service

sync
log "remounting / ro"
mount -o remount,ro /

# /etc is tmpfs-overlaid: removing our tmpfs override exposes the rootfs's
# original /etc/pm/sleep.wakesrc (which has serial0-0 as a wake source).
if [ -f /var/volatile/etc/pm/sleep.wakesrc ]; then
    log "removing tmpfs override of /etc/pm/sleep.wakesrc (rootfs version restored)"
    rm -f /var/volatile/etc/pm/sleep.wakesrc
fi

log "removing disable flag if present"
rm -f /data/internal/bt-keyboard.disabled

if [ "$PURGE" = 1 ]; then
    log "--purge: forgetting all paired devices"
    if systemctl is-active --quiet bluetooth; then
        for mac in $(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'); do
            bluetoothctl remove "$mac" >/dev/null 2>&1 || true
        done
    fi
    log "--purge: wiping /home/root/.bluetooth"
    rm -rf /home/root/.bluetooth/*/*
fi

systemctl daemon-reload

log "removing /home/root/bin scripts"
# Remove this script LAST so the others can be cleaned up first; this script
# is allowed to delete itself (POSIX rm + open fd).
rm -f /home/root/bin/bt-keyboard.sh \
      /home/root/bin/bt-keyboard-on.sh \
      /home/root/bin/bt-keyboard-watchdog.sh \
      /home/root/bin/install-rootfs-hooks.sh
self="$0"
log "done. removing self ($self)"
rm -f "$self"
