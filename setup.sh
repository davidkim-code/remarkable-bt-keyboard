#!/bin/sh
# setup.sh — install BT keyboard support on a reMarkable Paper Pro / Move.
#
# Run this from your laptop. It SCPs bin/*.sh to /home/root/bin/ on the rM and
# triggers install-rootfs-hooks.sh, which writes the boot-time pieces (kernel
# module loader + auto-reconnect watchdog) onto the rM's read-only rootfs.
#
# Re-run after every rM OS update — the rootfs partition gets swapped during
# the update, wiping anything under /lib. /home/root/bin survives, so you
# don't lose the actual scripts, only the boot-time hooks.
#
# Usage:
#   ./setup.sh HOST [-p PASSWORD] [-k "KEYBOARD NAME"]
#
#   HOST            SSH target. Typically root@10.11.99.1 (USB ethernet).
#                   For WLAN, use the IP shown in rM Settings (after running
#                   `rm-ssh-over-wlan on` on the device).
#   -p PASSWORD     The device root password. Optional. If omitted, ssh/scp
#                   prompt interactively (or use SSH key auth if you've set
#                   up keys). Requires `sshpass` if used.
#   -k "NAME"       Keyboard name to auto-pair after install. Optional.
#                   The keyboard must be in pairing mode when this step runs.
#
# Examples:
#   ./setup.sh root@10.11.99.1
#   ./setup.sh root@10.11.99.1 -p YOUR_ROOT_PASSWORD
#   ./setup.sh root@10.11.99.1 -p YOUR_ROOT_PASSWORD -k "WirelessKeyboard 1"

set -eu

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage 0
fi

HOST="$1"
shift

PASSWORD=""
KEYBOARD=""
while getopts ":p:k:" opt; do
    case "$opt" in
        p) PASSWORD="$OPTARG" ;;
        k) KEYBOARD="$OPTARG" ;;
        :) echo "Option -$OPTARG requires an argument." >&2; exit 2 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage ;;
    esac
done

# SSH options: skip known_hosts entirely. The rM USB-ethernet IP (10.11.99.1)
# is shared across rM devices — anyone with multiple rMs (or who reflashes)
# would otherwise hit "REMOTE HOST IDENTIFICATION HAS CHANGED!" The USB link
# is a direct cable, so MITM isn't a real threat. Override SSH_OPTS in the
# environment if you want stricter behavior.
: "${SSH_OPTS:=-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR}"

# Build ssh / scp wrappers that transparently use sshpass when a password was
# supplied. Without -p, fall through to native ssh/scp (which will use SSH
# keys, ssh-agent, or prompt for the password).
if [ -n "$PASSWORD" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
        cat >&2 <<EOF
ERROR: -p was given but sshpass is not installed.

Install it with:
  macOS:    brew install hudochenkov/sshpass/sshpass
  Debian:   sudo apt-get install sshpass
  Fedora:   sudo dnf install sshpass

Or omit -p and let ssh prompt for the password (or set up SSH key auth):
  ssh-copy-id $HOST
EOF
        exit 1
    fi
    SSH() { sshpass -p "$PASSWORD" ssh $SSH_OPTS "$HOST" "$@"; }
    SCP() { sshpass -p "$PASSWORD" scp $SSH_OPTS "$@"; }
else
    SSH() { ssh $SSH_OPTS "$HOST" "$@"; }
    SCP() { scp $SSH_OPTS "$@"; }
fi

REPO_DIR=$(cd "$(dirname "$0")" && pwd)

if [ ! -d "$REPO_DIR/bin" ] || [ -z "$(ls "$REPO_DIR"/bin/*.sh 2>/dev/null)" ]; then
    echo "ERROR: no bin/*.sh found next to setup.sh ($REPO_DIR/bin)" >&2
    exit 1
fi

echo "==> probing SSH connection to $HOST"
SSH 'echo "connected as $(id -un)@$(uname -n)"'

echo "==> ensuring /home/root/bin exists"
SSH 'mkdir -p /home/root/bin'

echo "==> copying bin/*.sh"
SCP "$REPO_DIR"/bin/*.sh "$HOST:/home/root/bin/"

echo "==> chmod +x"
SSH 'chmod +x /home/root/bin/*.sh'

echo "==> running install-rootfs-hooks.sh"
SSH '/home/root/bin/install-rootfs-hooks.sh'

if [ -n "$KEYBOARD" ]; then
    echo
    echo "==> auto-pairing keyboard \"$KEYBOARD\""
    echo "    Make sure the keyboard is in pairing mode RIGHT NOW (long-press the pair button)."
    echo "    The script will scan for ~12s, then pair."
    SSH "/home/root/bin/bt-keyboard.sh pair '$KEYBOARD'"
fi

cat <<EOF

============================================================
Done.

What's installed on the device:
  /home/root/bin/bt-keyboard.sh                     (CLI: pair / forget / list / enable / disable / status)
  /home/root/bin/bt-keyboard-on.sh                  (manual escape hatch)
  /home/root/bin/bt-keyboard-watchdog.sh            (auto-reconnect daemon, run by systemd)
  /home/root/bin/install-rootfs-hooks.sh            (re-installer for after OS updates)
  /home/root/bin/uninstall.sh                       (revert everything)
  /lib/systemd/system/btnxpuart-load.service        (loads the BT kernel module at boot)
  /lib/systemd/system/bt-no-suspend-wake.service    (stops BT from waking the rM from deep suspend)
  /lib/systemd/system/bt-keyboard-watchdog.service  (auto-reconnects paired keyboards)
  + symlinks in /lib/systemd/system/{sysinit,multi-user}.target.wants/

EOF

if [ -z "$KEYBOARD" ]; then
    cat <<EOF
Next: pair a keyboard. Put it in pairing mode (long-press pair button), then:
  $0 $HOST ${PASSWORD:+-p '$PASSWORD' }-k "Your Keyboard Name"

Or directly:
  ssh $HOST '/home/root/bin/bt-keyboard.sh pair "Your Keyboard Name"'

Other commands:
  ssh $HOST '/home/root/bin/bt-keyboard.sh status'        # state overview
  ssh $HOST '/home/root/bin/bt-keyboard.sh list'          # paired devices
  ssh $HOST '/home/root/bin/bt-keyboard.sh disable'       # turn off until re-enabled
  ssh $HOST '/home/root/bin/bt-keyboard.sh enable'        # turn back on
  ssh $HOST '/home/root/bin/bt-keyboard.sh forget NAME'   # remove one pairing
  ssh $HOST '/home/root/bin/bt-keyboard.sh forget --all'  # remove all pairings

EOF
fi

cat <<EOF
Verify the boot path: reboot the rM and turn on the keyboard. It should
connect on its own within ~15 seconds — no further action needed.

After every rM OS update, re-run:
  $0 $HOST ${PASSWORD:+-p '$PASSWORD'}
EOF
