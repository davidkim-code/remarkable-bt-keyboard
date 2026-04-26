# Make any Bluetooth keyboard work with your reMarkable

I really like to write with the stylus on my reMarkable. It puts you in a certain mode of thinking and it's great at jotting things down while you are working at your computer. The screen doesn't tire my eyes, the battery lasts for days, and nothing pings me. It's the best distraction-free writing setup I've found. Sometimes, I want to type. For example, when I make lists or need to write something longer that I want to transfer to Google Docs or Obsidian, for which I'd prefer having a keyboard.

There's one catch. The Type Folio for the Paper Pro is pricey, and you're stuck with whatever layout reMarkable picked. I reluctantly bought one. The Move doesn't even come with a keyboard option. If you already own a small Bluetooth keyboard you love, you can't just pair it and start typing.

So I went looking for a way around that.

## The keyboards I use for my reMarkable Move

I was looking for a usable keyboard that's not larger than the move and found one on Amazon. It even has a built in kickstand and is under $30. There are at least two brands that basically sell the same keyboard.

- **Doohoeek Universal Bluetooth Mini Keyboard.**
- **CACOE Wireless Keyboard.** Same shade of grey as the Move, so it looks like a matched set.

You can search either name on Amazon and find them.

## Why I built this

If you poke around the reMarkable community wiki, you'll find a [guide for getting Bluetooth working through developer mode](https://remarkable.guide/devel/device/bluetooth.html). I tried it and it works. The catch is that you have to run a few commands every time you reboot, every time the rM sleeps and wakes, and every time you turn the keyboard on or off. Not really usable.

I wanted something simpler. One install command, where you just hand it your SSH password and the keyboard name. The keyboard reconnects on its own after sleep, reboot, or power cycle. The Bluetooth chip stays off when the rM sleeps so the battery doesn't drain. And a clean uninstall in case I changed my mind. Friendly enough that someone who doesn't live in a terminal could still use it.

So I built it: github.com/davidkim-code/remarkable-bt-keyboard

Most of the code was vibe-coded with Claude (the AI). Two surprises came up that I want to flag, in case you read the code and wonder what's going on. First, the kernel module for Bluetooth ships disabled on the rM, which took some figuring out to bypass cleanly. Second, the rM's deep sleep is wired to wake on Bluetooth activity by default, which kills the whole point of letting the chip sleep. Both fixes are explained in the README if you're curious.

## How to install it

### Before you start

1. **Back up your reMarkable.** Turning on developer mode wipes the device. Use [reMarkable Connect](https://remarkable.com/connect) for cloud sync, or export your notebooks one by one before you flip the switch.
2. **Enable developer mode.** Search "developer mode" on `support.remarkable.com` for the official steps. You'll need to set a USB password while you're in there.
3. **Find your root password.** On the rM, go to Settings > Help > About > Copyrights and licenses. Scroll until you see a section labeled "GPLv3 Compliance". Above it there's a long random password. That's the one you'll use.
4. **Plug your rM into your computer** with the USB cable that came with it.

Now pick your operating system:
### macOS

1. Open the Terminal app (Cmd+Space, type Terminal).
2. Install Homebrew if you don't have it. Visit `brew.sh` and copy the one-line install command.
3. Install the helper that types the SSH password for you:
   ```
   brew install hudochenkov/sshpass/sshpass
   ```
4. Get the code:
   ```
   git clone https://github.com/davidkim-code/remarkable-bt-keyboard.git
   cd remarkable-bt-keyboard
   ```
5. Put your keyboard in pairing mode (long-press the pair button until the LED blinks).
6. Run the installer:
   ```
   ./setup.sh root@10.11.99.1 -p YOUR_ROOT_PASSWORD -k "Your Keyboard Name"
   ```
   Replace `YOUR_ROOT_PASSWORD` with the password from step 3 of "Before you start", and `"Your Keyboard Name"` with what your keyboard advertises (usually something like `WirelessKeyboard 1` or printed on the keyboard's manual).

### Linux

Same as macOS, but install sshpass through your package manager instead of Homebrew:

```
sudo apt install sshpass        # Ubuntu, Debian
sudo dnf install sshpass        # Fedora
```

Then continue from step 4 above.

### Windows

The simplest path is **WSL2** (Windows Subsystem for Linux). Open PowerShell as administrator and run `wsl --install`. Restart, open the new Ubuntu app, then follow the Linux instructions above.

If you'd rather not install WSL, install **Git for Windows** (`gitforwindows.org`), open Git Bash, and run the commands without the `-p` flag. Git Bash will ask for your password 3 or 4 times during setup.

```
./setup.sh root@10.11.99.1 -k "Your Keyboard Name"
```

## Day to day

After install, you mostly forget about it. The keyboard pairs once and then it just connects whenever you turn it on. A few commands you might want:

- See what's going on:
  ```
  ssh root@10.11.99.1 /home/root/bin/bt-keyboard.sh status
  ```
- Pair another keyboard (additive, doesn't kick the old one off):
  ```
  ssh root@10.11.99.1 '/home/root/bin/bt-keyboard.sh pair "Other Keyboard"'
  ```
- Forget a keyboard by name:
  ```
  ssh root@10.11.99.1 '/home/root/bin/bt-keyboard.sh forget "Some Keyboard"'
  ```
- Turn Bluetooth off until you turn it back on (saves battery):
  ```
  ssh root@10.11.99.1 /home/root/bin/bt-keyboard.sh disable
  ssh root@10.11.99.1 /home/root/bin/bt-keyboard.sh enable
  ```

After every reMarkable software update you'll need to run `setup.sh` again. The update wipes part of what we install. Your pairings stay though, so the keyboard reconnects without you having to re-pair.

## A few honest heads up

1. **Developer mode is a one-way door for your data unless you back up first.** reMarkable wipes the device when you flip the switch. Don't skip step 1.
2. **The code is mostly vibe-coded with AI.** I tested it on my Move and my Paper Pro, and it works for me, but I wouldn't be surprised if you find an edge case I missed. Open an issue on GitHub if you do.
3. **You're about to give an internet stranger root SSH access to your reMarkable.** Before you trust me, paste the repo into Gemini, ChatGPT, or Claude and ask if anything looks suspicious. The codebase is small, the answer comes back fast.

That's it. Enjoy typing on your reMarkable.

---

**Links**

- Code and install instructions: github.com/davidkim-code/remarkable-bt-keyboard
- The community Bluetooth guide that got me started: [remarkable.guide/devel/device/bluetooth.html](https://remarkable.guide/devel/device/bluetooth.html)
- reMarkable Connect (for backups): [remarkable.com/connect](https://remarkable.com/connect)
- Doohoeek and CACOE keyboards: search Amazon
