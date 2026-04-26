#!/bin/sh
# bt-keyboard — manage BT keyboards on the reMarkable.
#
# Subcommands:
#   pair NAME              Add a new keyboard. Substring-match on advertised name.
#                          Additive — does NOT forget existing pairings.
#                          Put the keyboard in pairing mode FIRST.
#                          Env: SCAN_SECS (default 12), PAIR_TIMEOUT (default 60),
#                               AGENT_CAP (default DisplayOnly),
#                               WAKE_ON_BT=yes (default no — keyboard does NOT
#                                   wake the device from suspend).
#   forget NAME            Remove the pairing for the keyboard whose name matches.
#   forget --all           Remove every pairing.
#   list                   Show paired keyboards with connection status.
#   enable                 Allow the watchdog to (re)connect; power adapter on.
#   disable                Stop reconnects, disconnect active links, power off
#                          the adapter. Saves battery while sleeping.
#   status                 Module / daemon / watchdog / flag / paired devices.
#   help                   This message.

set -eu

FLAG=/data/internal/bt-keyboard.disabled

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

bring_up() {
    /home/root/bin/bt-keyboard-on.sh >/dev/null 2>&1 || true
}

paired_macs() {
    bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'
}

# Look up a paired device's MAC by substring match on the listed name.
resolve_mac_by_name() {
    target="$1"
    bluetoothctl devices Paired 2>/dev/null | awk -v n="$target" '
        index($0, n) > 0 { print $2; exit }
    '
}

# Pretty-print one field from `bluetoothctl info` (handles multi-word values).
info_field() {
    info="$1"
    field="$2"
    printf '%s\n' "$info" | sed -n "s/^[[:space:]]*${field}: //p" | head -n 1
}

cmd_pair() {
    target="${1:-}"
    [ -n "$target" ] || { echo "Usage: bt-keyboard pair NAME" >&2; exit 2; }

    bring_up

    # Drive bluetoothctl through a FIFO so the agent stays registered across
    # the scan / pair / trust / connect commands.
    FIFO=$(mktemp -u /tmp/btpair.XXXXXX)
    mkfifo "$FIFO"
    LOG=/tmp/bt-pair.log
    : > "$LOG"
    bluetoothctl < "$FIFO" >>"$LOG" 2>&1 &
    BT_PID=$!
    exec 3>"$FIFO"

    # Surface passkey prompts to the user in real time.
    (
        tail -F "$LOG" 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                *Passkey:*|*"Enter passkey"*|*"Confirm passkey"*|*"PIN code"*)
                    printf '\n>>> %s\n>>> Type the digits on the keyboard, then press Enter.\n\n' "$line"
                    ;;
            esac
        done
    ) &
    WATCHER_PID=$!

    cleanup() {
        echo "exit" >&3 2>/dev/null || true
        exec 3>&- 2>/dev/null || true
        wait "$BT_PID" 2>/dev/null || true
        kill "$WATCHER_PID" 2>/dev/null || true
        rm -f "$FIFO"
    }
    trap cleanup EXIT

    send() { printf '%s\n' "$1" >&3; sleep 0.2; }

    send "power on"
    send "agent off"
    send "agent ${AGENT_CAP:-DisplayOnly}"
    send "default-agent"
    send "scan on"

    echo "[bt-keyboard pair] scanning for '$target' (max ${SCAN_SECS:-12}s) — keyboard must be in pairing mode"
    mac=""
    i=0
    while [ "$i" -lt "${SCAN_SECS:-12}" ]; do
        mac=$(bluetoothctl devices 2>/dev/null \
            | awk -v n="$target" 'index($0, n) > 0 { print $2; exit }')
        [ -n "$mac" ] && break
        sleep 1
        i=$((i+1))
    done
    send "scan off"

    if [ -z "$mac" ]; then
        echo "[bt-keyboard pair] did not find '$target' — is the keyboard in pairing mode?" >&2
        echo "[bt-keyboard pair] tip: tail $LOG for raw bluetoothctl output" >&2
        exit 1
    fi

    echo "[bt-keyboard pair] found $mac, pairing — watch for the passkey"
    send "pair $mac"

    paired=""
    i=0
    while [ "$i" -lt "${PAIR_TIMEOUT:-60}" ]; do
        paired=$(bluetoothctl info "$mac" 2>/dev/null | awk '/Paired:/ {print $2}')
        [ "$paired" = "yes" ] && break
        sleep 1
        i=$((i+1))
    done
    if [ "$paired" != "yes" ]; then
        echo "[bt-keyboard pair] pair did not complete (Paired=$paired). See $LOG" >&2
        exit 1
    fi

    send "trust $mac"
    if [ "${WAKE_ON_BT:-no}" = "yes" ]; then
        send "menu device"
        send "wake-allowed $mac yes"
        send "back"
    fi
    send "connect $mac"
    sleep 3

    echo "[bt-keyboard pair] done:"
    bluetoothctl info "$mac" \
        | awk '/Name:|Paired:|Trusted:|Connected:|WakeAllowed:/ {print "    " $0}'
}

cmd_forget() {
    arg="${1:-}"
    [ -n "$arg" ] || { echo "Usage: bt-keyboard forget NAME | --all" >&2; exit 2; }

    bring_up

    if [ "$arg" = "--all" ]; then
        count=0
        for mac in $(paired_macs); do
            bluetoothctl remove "$mac" >/dev/null 2>&1 || true
            count=$((count+1))
        done
        echo "[bt-keyboard forget] removed $count pairing(s)"
    else
        mac=$(resolve_mac_by_name "$arg")
        if [ -z "$mac" ]; then
            echo "[bt-keyboard forget] no paired device matches '$arg'. Currently paired:" >&2
            bluetoothctl devices Paired >&2 || true
            exit 1
        fi
        bluetoothctl remove "$mac" >/dev/null 2>&1
        echo "[bt-keyboard forget] removed $mac (matched '$arg')"
    fi
}

cmd_list() {
    bring_up
    has_any=0
    for mac in $(paired_macs); do
        has_any=1
        info=$(bluetoothctl info "$mac" 2>/dev/null)
        name=$(info_field "$info" Name)
        connected=$(info_field "$info" Connected)
        trusted=$(info_field "$info" Trusted)
        printf '  %s  %-25s  trusted=%s  connected=%s\n' "$mac" "${name:-?}" "${trusted:-?}" "${connected:-?}"
    done
    [ "$has_any" = 0 ] && echo "(no paired devices)"
}

cmd_enable() {
    if [ -f "$FLAG" ]; then
        rm -f "$FLAG"
        echo "[bt-keyboard enable] cleared $FLAG"
    else
        echo "[bt-keyboard enable] already enabled (no flag at $FLAG)"
    fi
    bring_up
    bluetoothctl power on >/dev/null 2>&1 || true
}

cmd_disable() {
    mkdir -p "$(dirname "$FLAG")"
    : > "$FLAG"
    echo "[bt-keyboard disable] flag set at $FLAG"
    if systemctl is-active --quiet bluetooth; then
        for mac in $(paired_macs); do
            bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
        done
        bluetoothctl power off >/dev/null 2>&1 || true
        echo "[bt-keyboard disable] adapter powered off"
    fi
}

cmd_status() {
    if lsmod | grep -q '^btnxpuart'; then
        echo "module btnxpuart:           loaded"
    else
        echo "module btnxpuart:           NOT loaded"
    fi
    echo "service bluetooth:          $(systemctl is-active bluetooth 2>/dev/null || echo unknown)"
    echo "service bt-keyboard-watchdog: $(systemctl is-active bt-keyboard-watchdog 2>/dev/null || echo unknown)"
    if [ -f "$FLAG" ]; then
        echo "user state:                 DISABLED (flag at $FLAG)"
    else
        echo "user state:                 enabled"
    fi
    if systemctl is-active --quiet bluetooth; then
        powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2}')
        echo "adapter:                    Powered=$powered"
    fi
    echo
    echo "Paired devices:"
    cmd_list
}

cmd="${1:-}"
[ -n "$cmd" ] || usage 0
shift || true

case "$cmd" in
    pair)        cmd_pair "$@" ;;
    forget)      cmd_forget "$@" ;;
    list)        cmd_list "$@" ;;
    enable)      cmd_enable "$@" ;;
    disable)     cmd_disable "$@" ;;
    status)      cmd_status "$@" ;;
    -h|--help|help) usage 0 ;;
    *) echo "Unknown subcommand: $cmd" >&2; usage 2 ;;
esac
