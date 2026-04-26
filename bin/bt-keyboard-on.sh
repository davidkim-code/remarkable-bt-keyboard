#!/bin/sh
# bt-keyboard-on.sh — manual escape hatch: load btnxpuart, start bluetoothd,
# and try to (re)connect any paired keyboard.
#
# After install-rootfs-hooks.sh has run, you don't normally need this — the
# btnxpuart-load.service handles module load on boot, the watchdog handles
# reconnects. This script is for ad-hoc debugging or recovery.
#
# Usage:
#   /home/root/bin/bt-keyboard-on.sh              # all paired devices
#   KEYBOARD_MAC=AA:BB:... bt-keyboard-on.sh      # only this MAC

set -eu

log() { printf '[bt-keyboard] %s\n' "$*"; }

# 1. Load the BT UART driver if it isn't already loaded.
if ! lsmod | grep -q '^btnxpuart'; then
    log "loading btnxpuart"
    modprobe btnxpuart
fi

# 2. Wait for the adapter to appear in sysfs.
i=0
while [ ! -d /sys/class/bluetooth ] && [ $i -lt 20 ]; do
    sleep 0.1
    i=$((i+1))
done
[ -d /sys/class/bluetooth ] || { log "no /sys/class/bluetooth — adapter never came up"; exit 1; }

# 3. Start bluetoothd. Its ConditionPathIsDirectory=/sys/class/bluetooth is now met.
#    AutoEnable=true in /etc/bluetooth/main.conf powers the adapter on automatically.
if ! systemctl is-active --quiet bluetooth; then
    log "starting bluetooth.service"
    systemctl start bluetooth
fi

# 4. Wait for the adapter to be powered on.
i=0
while [ "$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2}')" != "yes" ] && [ $i -lt 30 ]; do
    sleep 0.2
    i=$((i+1))
done

# 5. Decide which MACs to try. Trusted devices auto-reconnect on their own when
#    they come into range — this just surfaces an immediate connection if the
#    keyboard is already powered on, and lets us print status.
if [ -n "${KEYBOARD_MAC:-}" ]; then
    macs="$KEYBOARD_MAC"
else
    macs=$(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}')
fi

if [ -z "$macs" ]; then
    log "no paired devices yet — pair one with: /home/root/bin/bt-keyboard.sh pair NAME"
    exit 0
fi

for mac in $macs; do
    log "connecting $mac"
    if bluetoothctl connect "$mac" >/dev/null 2>&1; then
        log "  connected"
    else
        log "  not in range / off — will auto-reconnect when powered (bonded + trusted)"
    fi
    bluetoothctl info "$mac" 2>/dev/null \
        | awk '/Name:|Paired:|Trusted:|Connected:/ {print "    " $0}'
done
