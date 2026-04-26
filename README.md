# remarkable-bt-keyboard

Persistent Bluetooth keyboard support for the **reMarkable Paper Pro** and **reMarkable Paper Pro Move** in developer mode.

Pair your keyboard once. Reboot, sleep/wake, power-cycle the keyboard — it just reconnects. No more manual `modprobe` / `bluetoothctl` after every state change.

## What you get

- **Auto-loads `btnxpuart`** at boot (working around the rM's stock kmod blacklist).
- **Auto-starts `bluetoothd`** with the adapter powered on (already wired by stock rM once the module is loaded).
- **Auto-reconnects** any paired+trusted keyboard via a small systemd watchdog (BlueZ 5.72 doesn't reliably re-attach LE peripherals after they power-cycle).
- **Pairing data persists** across reboots and OS updates because rM already bind-mounts `/var/lib/bluetooth` from `/home`. We don't touch that.
- **One command to set up.** One command to recover after an OS update.

## Tested on

- reMarkable Paper Pro Move — Codex Linux 5.6.75, IMG 3.26.0.68 (kernel hostname `imx93-chiappa`)
- reMarkable Paper Pro — Codex Linux on `imx8mm-ferrari` (different SoC, same OS branch — works identically)

The two devices ship slightly different SoCs (Move = i.MX93, Paper Pro = i.MX8MM) but the same Codex Linux build, the same `btnxpuart` blacklist, and the same BlueZ version, so the install steps are identical.

## Requirements

- A reMarkable Paper Pro or Paper Pro Move with **developer mode** enabled. (Search "developer mode" on `support.remarkable.com` for the official steps. Heads up, enabling it usually wipes the device, so back up first via reMarkable Connect or by exporting your notebooks.)
- SSH reachable over USB-ethernet (default `root@10.11.99.1`) or WLAN (after running `rm-ssh-over-wlan on` on the device).
- A computer with `ssh` and `scp`. macOS and Linux have these built in. On **Windows**, install [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) (`wsl --install` in PowerShell as admin) and use the Ubuntu shell, or install [Git for Windows](https://gitforwindows.org/) and use Git Bash.

## Quick start

```sh
git clone https://github.com/davidkim-code/remarkable-bt-keyboard.git
cd remarkable-bt-keyboard

# Install + pair in one command. Put the keyboard in pairing mode FIRST.
./setup.sh root@10.11.99.1 -p YOUR_ROOT_PASSWORD -k "Your Keyboard Name"
```

`setup.sh` arguments:

| Position / flag | Required? | Description |
| --- | --- | --- |
| `HOST` (positional) | yes | SSH target. Typically `root@10.11.99.1` over USB ethernet. For WLAN, run `rm-ssh-over-wlan on` on the device first and use the rM's WLAN IP. |
| `-p PASSWORD` | no | Device root password. Uses [`sshpass`](#sshpass) for non-interactive SSH. Omit if you've set up SSH key auth or are happy to type the password each time. |
| `-k "NAME"` | no | Advertised name of a keyboard to pair right after install. The keyboard must be in pairing mode (long-press the pair button) when this step runs. Omit to skip pairing. |

Examples:

```sh
# Install only (interactive password prompt)
./setup.sh root@10.11.99.1

# Install + pair, password supplied
./setup.sh root@10.11.99.1 -p hunter2 -k "WirelessKeyboard 1"

# Install only, password supplied (pair later)
./setup.sh root@10.11.99.1 -p hunter2
```

To pair another keyboard later (additive — does not forget existing ones), run setup again with `-k`, or invoke the dispatcher directly:

```sh
./setup.sh root@10.11.99.1 -p hunter2 -k "My Other Keyboard"
# or
ssh root@10.11.99.1 '/home/root/bin/bt-keyboard.sh pair "My Other Keyboard"'
```

You can pair as many keyboards as you want — they all coexist, and the watchdog reconnects whichever one happens to be on.

After install, the keyboard reconnects on its own after reboots, sleep/wake, and keyboard power-cycles. No more manual `bluetoothctl`.

### sshpass

`-p PASSWORD` requires `sshpass`. Install it the way that fits your OS:

- **macOS** (with [Homebrew](https://brew.sh)):
  ```sh
  brew install hudochenkov/sshpass/sshpass
  ```
- **Linux** (Debian / Ubuntu):
  ```sh
  sudo apt install sshpass
  ```
  Fedora: `sudo dnf install sshpass`.
- **Windows / WSL Ubuntu**:
  ```sh
  sudo apt install sshpass
  ```
- **Windows / Git Bash**: there's no easy `sshpass` build. Drop `-p` and let `ssh` prompt for the password each time it's used (it's used 3 or 4 times per run).

If you'd rather not deal with `sshpass` at all, drop `-p` on any platform and let `ssh` prompt. For repeated use, set up SSH key auth instead:

```sh
ssh-copy-id root@10.11.99.1
```

## After an rM OS update

rM uses A/B partition swaps for OS updates, so anything written to `/lib/...` gets wiped. Re-run the setup:

```sh
./setup.sh root@10.11.99.1 -p YOUR_PASSWORD
```

This is **idempotent** — safe to run any number of times. Pairing data under `/home/root/.bluetooth/` survives updates and isn't touched, so you don't need to re-pair the keyboard.

## How it works (and why this is harder than it sounds)

If you read the [official-ish reMarkable Bluetooth guide](https://remarkable.guide/devel/device/bluetooth.html), it suggests editing `/etc/modules-load.d/`, `/etc/bluetooth/main.conf`, etc. On the **Paper Pro** and **Move** running Codex Linux 5.6.x, that mostly fails because the filesystem layout has gotchas:

```
mount | grep -E "/etc|/home|/var|/lib"
overlay on /etc           upperdir=/var/volatile/etc          # tmpfs (lost on reboot)
overlay on /var/lib       upperdir=/var/volatile/lib          # tmpfs (lost on reboot)
/dev/mmcblk0p3            on /                                # ext4 ro (rootfs A/B partition)
/dev/mmcblk0p1            on /data                            # ext4 rw, persistent
/dev/mapper/home...       on /home                            # encrypted ext4, persistent
/dev/mapper/home...       on /var/lib/bluetooth               # bind from /home/root/.bluetooth
```

So:

| Location | Persistence | Notes |
| --- | --- | --- |
| `/etc/...` | ❌ tmpfs | Lost on every reboot. Don't put real config here. |
| `/home/root/...` | ✅ persistent | Encrypted ext4. Survives reboots **and** OS updates. |
| `/lib/...` (= `/usr/lib/...`) | ⚠️ persistent until OS update | Read-only rootfs; re-mount rw to write. Wiped on next A/B update. |
| `/var/lib/bluetooth` | ✅ persistent | Bind-mounted from `/home/root/.bluetooth`. Pairing keys / trust flags / `WakeAllowed` survive. |

The two real obstacles to "just works":

### 1. The kernel module is blacklisted

`/etc/modprobe.d/btnxpuart.conf` ships with `blacklist btnxpuart`. `systemd-modules-load` honors the blacklist (via libkmod), so dropping a file in `modules-load.d/` to autoload the module does nothing.

**Direct** `modprobe btnxpuart` ignores the blacklist (modprobe only consults the blacklist when resolving aliases), so the workaround is a tiny `oneshot` systemd service:

```ini
[Unit]
Description=Load btnxpuart kernel module
DefaultDependencies=no
Before=bluetooth.service sysinit.target
ConditionPathExists=!/sys/class/bluetooth

[Service]
Type=oneshot
ExecStart=/usr/sbin/modprobe btnxpuart
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
```

This unit lives in `/lib/systemd/system/` (rootfs), so it survives reboots. Once it runs, `bluetoothd`'s `ConditionPathIsDirectory=/sys/class/bluetooth` becomes true and `bluetoothd` auto-starts. The stock `AutoEnable=true` in `/etc/bluetooth/main.conf` powers the adapter on automatically.

### 2. BlueZ 5.72 doesn't reliably auto-reconnect peripherals

After a paired LE peripheral disconnects (keyboard powered off, deep idle, etc.), BlueZ should re-establish a background connection when the device advertises again. In practice on this rM build, it doesn't reliably — the keyboard stays stuck `Connected: no`.

A small watchdog handles this: every 15 seconds, for any paired+trusted device that's currently disconnected, issue `bluetoothctl connect <mac>`. The call is fast and idempotent — if the device isn't reachable, it fails immediately and we try again next tick.

The watchdog runs as a long-running systemd unit, also installed in `/lib/systemd/system/`.

### 3. BT is armed as a wake source for deep suspend

`/etc/pm/sleep.wakesrc` ships with `serial0-0` (the BT UART) listed. The rM's pre-suspend hook (`/lib/systemd/system-sleep/sleep-wakesources.sh`) reads that file and registers each entry as a kernel wake source — so any BLE traffic during deep suspend wakes the SoC. BlueZ's `WakeAllowed=false` setting is independent of this (it only governs whether *BlueZ* propagates the wake event upstack — the kernel still wakes the system either way).

We strip `serial0-0` on every boot via a tiny `oneshot` service. `/etc` is tmpfs-overlaid, so the edit has to re-run every boot — cheap (one `sed -i` call). After the strip, the BT chipset can fully sleep when the rM does. You wake the rM with the power button or the folio sensor; the watchdog reconnects the keyboard within ~15 s.

If you want BT-triggered wake (rare — costs continuous battery during suspend), remove the `bt-no-suspend-wake.service` symlink and reboot.

### Pairing keys already persist (don't reinvent this)

You don't need to back up or restore pairing data. The stock unit `/lib/systemd/system/var-lib-bluetooth.mount` bind-mounts `/home/root/.bluetooth` to `/var/lib/bluetooth`, so the BlueZ database lives on the encrypted persistent partition. Reboots, OS updates, even partition swaps — pairing survives.

## Files

```
.
├── README.md                         # this file
├── LICENSE                           # MIT
├── setup.sh                          # laptop-side bootstrap
└── bin/                              # scripts that run on the rM
    ├── install-rootfs-hooks.sh       # installs the boot-time pieces (rootfs)
    ├── uninstall.sh                  # reverts everything install-rootfs-hooks did
    ├── bt-keyboard.sh                # CLI: pair / forget / list / enable / disable / status
    ├── bt-keyboard-on.sh             # manual escape hatch — load module + connect
    └── bt-keyboard-watchdog.sh       # the auto-reconnect loop (run by systemd)
```

## CLI: `bt-keyboard.sh`

A single dispatcher with subcommands. Run on the device (over SSH):

```sh
ssh root@10.11.99.1 '/home/root/bin/bt-keyboard.sh <subcommand> [args]'
```

| Subcommand | What it does |
| --- | --- |
| `pair NAME` | Add a new keyboard. Substring match on the advertised name. **Additive** — does not touch other pairings. Put the keyboard in pairing mode first. |
| `forget NAME` | Remove the pairing whose name matches `NAME`. |
| `forget --all` | Remove every pairing. |
| `list` | Show all paired keyboards with trusted/connected state. |
| `enable` | Allow the watchdog to reconnect; powers the adapter on. |
| `disable` | Set a flag, disconnect any active link, power the adapter off. Saves battery while you're not using a keyboard. |
| `status` | Module / daemon / watchdog / flag / paired devices in one view. |

### Pairing details

The `pair` subcommand:

1. Loads the BT stack (calls `bt-keyboard-on.sh`).
2. Drives `bluetoothctl` via a FIFO so the pairing agent stays registered.
3. Scans for the named device, then pairs + trusts + connects.
4. **Does not** set `WakeAllowed=true` by default — your keyboard will not wake the rM from suspend (saves battery; you wake the rM with the power button, the keyboard reconnects within seconds).

Env-var overrides:

- `SCAN_SECS=20 bt-keyboard.sh pair "Foo"` — longer scan window (default 12 s).
- `PAIR_TIMEOUT=90 bt-keyboard.sh pair "Foo"` — longer SMP wait (default 60 s).
- `AGENT_CAP=KeyboardDisplay bt-keyboard.sh pair "Foo"` — different agent capability (default `DisplayOnly`).
- `WAKE_ON_BT=yes bt-keyboard.sh pair "Foo"` — opt in to BT-triggered wake-from-suspend (rare; costs continuous battery while suspended).

### Disable / enable

Use `disable` when you want the rM to truly sleep (no BT chipset listening) and don't need a keyboard:

```sh
ssh root@10.11.99.1 '/home/root/bin/bt-keyboard.sh disable'
```

This:
- Creates `/data/internal/bt-keyboard.disabled` (`/data` is rw-persistent).
- Disconnects any currently linked keyboards.
- Powers the adapter off.

The watchdog checks the flag on every tick and skips reconnect attempts while it exists. Re-enable with:

```sh
ssh root@10.11.99.1 '/home/root/bin/bt-keyboard.sh enable'
```

Toggling is cheap — the flag check is a single `stat()`. No need to reboot.

## Troubleshooting

### Quick state check

```sh
ssh root@10.11.99.1 '/home/root/bin/bt-keyboard.sh status'
```

Sample output:

```
module btnxpuart:           loaded
service bluetooth:          active
service bt-keyboard-watchdog: active
user state:                 enabled
adapter:                    Powered=yes

Paired devices:
  AA:BB:CC:DD:EE:FF  WirelessKeyboard 1        trusted=yes  connected=yes
```

### Pair fails with `AuthenticationCanceled`

The keyboard fell out of pairing mode before the SMP exchange completed. Long-press the pair button again and re-run `bt-keyboard.sh pair` immediately.

### Inspect raw HCI exchange

```sh
ssh root@10.11.99.1 btmon -t -i hci0
```

### Keyboard "Connected: yes" but typing doesn't work

Check `/proc/bus/input/devices` for a line like `WirelessKeyboard 1 Keyboard`. Some combo keyboards expose both keyboard and mouse interfaces — both should appear. If they don't, try `bluetoothctl disconnect <MAC>` then wait — the watchdog will re-attach.

### Reset everything

```sh
# Forget all pairings, then nuke BlueZ state and the kernel module
ssh root@10.11.99.1 '
  /home/root/bin/bt-keyboard.sh forget --all
  systemctl stop bt-keyboard-watchdog bluetooth
  rm -rf /home/root/.bluetooth/*/*
  modprobe -r btnxpuart bluetooth crc8 2>/dev/null
'
```

Then re-pair (each `bt-keyboard.sh pair` call is additive, so re-pair as many keyboards as you want).

## Uninstall

To revert everything `setup.sh` did:

```sh
ssh root@10.11.99.1 /home/root/bin/uninstall.sh
```

This removes the three systemd units, restores `/etc/pm/sleep.wakesrc` (for the current uptime — it'll reset on next boot anyway), removes the `disable` flag, and deletes the scripts under `/home/root/bin/`. **Pairing data is kept** so a later re-install doesn't make you re-pair.

To also wipe pairing data and forget every keyboard:

```sh
ssh root@10.11.99.1 /home/root/bin/uninstall.sh --purge
```

After uninstall the rM is back to stock — the BT module is still loaded for the current uptime, but won't auto-load on next boot, and `bluetoothd` will go back to its default behavior.

## What this does to your reMarkable

Honest accounting of every change:

| Where | What | Survives reboot? | Survives OS update? |
| --- | --- | --- | --- |
| `/home/root/bin/*.sh` | Five shell scripts (`bt-keyboard.sh`, `bt-keyboard-on.sh`, `bt-keyboard-watchdog.sh`, `install-rootfs-hooks.sh`, `uninstall.sh`) | ✅ | ✅ |
| `/lib/systemd/system/btnxpuart-load.service` | Module loader unit | ✅ | ❌ — re-run `setup.sh` |
| `/lib/systemd/system/sysinit.target.wants/btnxpuart-load.service` | Symlink (enables the loader) | ✅ | ❌ |
| `/lib/systemd/system/bt-no-suspend-wake.service` | Strips `serial0-0` (BT UART) from `/etc/pm/sleep.wakesrc` so BT can't wake the rM from deep suspend | ✅ | ❌ |
| `/lib/systemd/system/sysinit.target.wants/bt-no-suspend-wake.service` | Symlink | ✅ | ❌ |
| `/lib/systemd/system/bt-keyboard-watchdog.service` | Watchdog unit | ✅ | ❌ |
| `/lib/systemd/system/multi-user.target.wants/bt-keyboard-watchdog.service` | Symlink (enables the watchdog) | ✅ | ❌ |

The setup script briefly remounts `/` as read-write to add the `/lib/...` files, then remounts read-only. The blacklist file (`/etc/modprobe.d/btnxpuart.conf`) is **not modified** — the loader service simply uses direct `modprobe` which bypasses it.

No firmware modifications. No bootloader changes. No partition repartitioning. To fully revert, run `/home/root/bin/uninstall.sh` (or `--purge` to also forget paired keyboards).

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- The [reMarkable Wiki Bluetooth guide](https://remarkable.guide/devel/device/bluetooth.html) for the initial pointer at `btnxpuart`.
- BlueZ devs for `btmon` — invaluable for understanding why initial pairing attempts hit `AuthenticationCanceled`.

## Disclaimer

This software touches your reMarkable's read-only rootfs (briefly, with `mount -o remount,rw /`). I has used this on my own Move and Paper Pro without issue, but you take all risk. Reverting is `/home/root/bin/uninstall.sh`. Pairing data and your normal rM data are not touched unless you pass `--purge`.
