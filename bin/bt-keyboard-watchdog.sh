#!/bin/sh
# bt-keyboard-watchdog.sh — keep paired+trusted BT keyboards reconnected.
#
# Skips work when the user has disabled BT via `bt-keyboard disable` (which
# touches /data/internal/bt-keyboard.disabled).
#
# BlueZ on this device doesn't reliably re-establish a background LE connection
# after the peripheral power-cycles (chipset goes into deep idle, advertising
# packets get missed). This watchdog polls every $INTERVAL seconds and issues
# a `bluetoothctl connect` for any paired+trusted device that's currently
# disconnected. Calls are idempotent; if the device is unreachable, the call
# fails fast and we try again next tick.
#
# Run via /lib/systemd/system/bt-keyboard-watchdog.service.

set -u

INTERVAL="${INTERVAL:-15}"
FLAG=/data/internal/bt-keyboard.disabled

# Wait for the BT stack to be up before we start polling.
i=0
while [ ! -d /sys/class/bluetooth ] && [ $i -lt 60 ]; do
    sleep 1
    i=$((i+1))
done

while true; do
    if [ ! -f "$FLAG" ] && systemctl is-active --quiet bluetooth; then
        bluetoothctl devices Paired 2>/dev/null | awk '{print $2}' | while read -r mac; do
            [ -n "$mac" ] || continue
            info=$(bluetoothctl info "$mac" 2>/dev/null)
            case "$info" in
                *"Trusted: yes"*)
                    case "$info" in
                        *"Connected: no"*)
                            bluetoothctl connect "$mac" >/dev/null 2>&1 || true
                            ;;
                    esac
                    ;;
            esac
        done
    fi
    sleep "$INTERVAL"
done
