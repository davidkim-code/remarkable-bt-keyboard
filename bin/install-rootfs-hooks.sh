#!/bin/sh
# install-rootfs-hooks.sh — install the persistent boot-time pieces.
#
# Writes three systemd units under /lib/systemd/system/ (the read-only rootfs,
# briefly remounted rw):
#   btnxpuart-load.service       loads the BT kernel module at boot
#                                (modprobe by-name bypasses the stock blacklist
#                                at /etc/modprobe.d/btnxpuart.conf, which makes
#                                modules-load.d/ unusable here)
#   bt-no-suspend-wake.service   strips serial0-0 (the BT UART) from
#                                /etc/pm/sleep.wakesrc so BT can't wake the
#                                rM from deep suspend (must re-run every boot
#                                because /etc is a tmpfs overlay)
#   bt-keyboard-watchdog.service runs bt-keyboard-watchdog.sh, which polls and
#                                reconnects paired+trusted keyboards
#
# Idempotent — re-run after every rM OS update. The A/B partition swap during
# update wipes /lib; /home/root survives.

set -eu

log() { printf '[install] %s\n' "$*"; }

log "remounting / rw"
mount -o remount,rw /

log "writing /lib/systemd/system/btnxpuart-load.service"
cat > /lib/systemd/system/btnxpuart-load.service <<'UNIT'
[Unit]
Description=Load btnxpuart kernel module
DefaultDependencies=no
Before=bluetooth.service sysinit.target
After=systemd-modules-load.service
ConditionPathExists=!/sys/class/bluetooth

[Service]
Type=oneshot
ExecStart=/usr/sbin/modprobe btnxpuart
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
UNIT

mkdir -p /lib/systemd/system/sysinit.target.wants
ln -sf /lib/systemd/system/btnxpuart-load.service \
    /lib/systemd/system/sysinit.target.wants/btnxpuart-load.service

log "writing /lib/systemd/system/bt-no-suspend-wake.service"
cat > /lib/systemd/system/bt-no-suspend-wake.service <<'UNIT'
[Unit]
Description=Drop BT (serial0-0) from /etc/pm/sleep.wakesrc so it cannot wake the rM from deep suspend
DefaultDependencies=no
Before=sysinit.target sleep.target
ConditionPathExists=/etc/pm/sleep.wakesrc

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sed -i "/^serial0-0$/d" /etc/pm/sleep.wakesrc'
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
UNIT

ln -sf /lib/systemd/system/bt-no-suspend-wake.service \
    /lib/systemd/system/sysinit.target.wants/bt-no-suspend-wake.service

log "writing /lib/systemd/system/bt-keyboard-watchdog.service"
cat > /lib/systemd/system/bt-keyboard-watchdog.service <<'UNIT'
[Unit]
Description=Reconnect paired BT keyboards
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=simple
ExecStart=/home/root/bin/bt-keyboard-watchdog.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

mkdir -p /lib/systemd/system/multi-user.target.wants
ln -sf /lib/systemd/system/bt-keyboard-watchdog.service \
    /lib/systemd/system/multi-user.target.wants/bt-keyboard-watchdog.service

sync
log "remounting / ro"
mount -o remount,ro /

log "reloading systemd and starting services"
systemctl daemon-reload
systemctl start btnxpuart-load.service || true
systemctl start bt-no-suspend-wake.service || true
systemctl restart bt-keyboard-watchdog.service || systemctl start bt-keyboard-watchdog.service

log "done. installed:"
ls -la /lib/systemd/system/btnxpuart-load.service \
       /lib/systemd/system/sysinit.target.wants/btnxpuart-load.service \
       /lib/systemd/system/bt-no-suspend-wake.service \
       /lib/systemd/system/sysinit.target.wants/bt-no-suspend-wake.service \
       /lib/systemd/system/bt-keyboard-watchdog.service \
       /lib/systemd/system/multi-user.target.wants/bt-keyboard-watchdog.service
