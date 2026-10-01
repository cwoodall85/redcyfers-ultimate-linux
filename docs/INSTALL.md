# Installing RedCyfer's Ultimate Linux

You'll need:

- A 64-bit PC (AMD or Intel) with 8 GB of RAM or more and 40 GB of free disk space.
- A **16 GB or larger USB stick**. Everything on it will be erased.
- An internet connection, for updates and for Claude.
- About an hour.

This is an early release. Back up anything you care about before you
start, and tell us what happens in the chat:
https://chat.redcyfer.com/join

## 1. Download and check the image

From https://dl.redcyfer.com/releases/, download the newest `.img.xz`
file and its `.sha256` file into the same folder.

Check the download wasn't damaged:

- **Linux:** `sha256sum -c ultimate-linux-*.img.xz.sha256`. **macOS:** `shasum -a 256 -c ultimate-linux-*.img.xz.sha256`. Either should say `OK`.
- **Windows (PowerShell):** run `Get-FileHash .\ultimate-linux-*.img.xz`, then compare the hash with the one in the `.sha256` file.

## 2. Write it to the USB stick

- **Windows or macOS:** use **balenaEtcher** (https://etcher.balena.io). Choose the `.img.xz` file (Etcher unpacks it itself), choose the USB stick, then Flash.
- **Linux:**

  ```
  xz -dc ultimate-linux-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
  ```

  Replace `/dev/sdX` with the USB stick (check with `lsblk`; the wrong disk gets erased).

## 3. Get the PC ready

### If the PC has Windows on it

**Check BitLocker first.**
- Open Settings → Privacy & security → **Device encryption** (or search for "BitLocker").
- If it's on, save the 48-digit **recovery key**: print it, or find it at https://account.microsoft.com/devicesrecoverykey.
- Changing Secure Boot (next step) makes Windows ask for this key once. Without it, Windows can't open its drive.

**To keep Windows and add Ultimate next to it, make room first.**
1. Open **Disk Management**: right-click Start, then Disk Management.
2. Right-click the big `C:` partition and choose **Shrink Volume**.
3. Shrink it by at least 40,000 MB (100,000 MB is comfortable).
4. Leave the new space "Unallocated". Don't create a partition in it.

### Turn Secure Boot off

Restart and open the firmware setup. The key is usually **F2**, **Del** or
**F10** as the PC starts; it's often shown on screen. In the **Boot** or
**Security** menu, set **Secure Boot** to **Disabled**, then save and exit.

> Rather keep Secure Boot on? You can: at the first boot from the stick a
> blue "MokManager" screen appears.
> 1. Choose **Enroll key from disk**.
> 2. Pick `ultimate-mok.cer`, then **Continue** and **Yes**.
> 3. Reboot.
>
> You need a wired (USB) keyboard on that screen; Bluetooth keyboards don't
> work that early.

## 4. Boot from the USB stick

Plug the stick in and restart. Press the **boot menu** key (often **F12**,
**F11**, **F8** or **Esc**) and choose the USB stick (the "UEFI" entry if
there are two).

The live desktop starts by itself, with no password. Everything works here.
It runs from the stick, so it's slower than an installed system.

## 5. Install

Double-click **Install RedCyfer's Ultimate Linux** on the desktop. A
terminal asks a few questions:

- **How:**
  - **alongside** keeps Windows (or another Linux) and uses the free space you made in step 3. You choose the system at each start-up.
  - **whole** erases the whole disk you pick and puts only Ultimate on it.
- **Disk:** the PC's disk, not the USB stick. Check the size it shows.
- **Your name, user name, password, computer name and a root (administrator) password.**

Type `yes` to confirm. Installing takes 5 to 15 minutes. When it says
it's done, remove the USB stick and restart.

## 6. First start

- Log in with the user name and password you chose.
- A terminal offers to **install Claude Code** (Anthropic's official installer) and then to **sign in** with your Claude account; a browser window opens.
  - Claude needs a Claude subscription (Pro or Max) or an API key.
  - Skip it if you like, and run `ultimate-claude-welcome` later.
- Then press **Meta+Space** (the Windows key + Space) and ask Claude anything about the computer: "why is my fan loud?", "what's using my disk?".

**Updates:** open a terminal and run `sudo pacman -Syu`. Every package is signed.

## 7. Tell us how it went

Join the chat at https://chat.redcyfer.com/join (a sign-in link is emailed
to you). You'll see the **#ultimate-linux** channel.

You can also chat from Ultimate Mail:
1. On the chat website, press **Use in Ultimate Mail** and copy the token.
2. In Ultimate Mail, open Settings → Chat and paste it.

## If something goes wrong

- **The PC doesn't boot the USB stick:** turn off **Fast Boot** in the firmware too, and make sure you picked the "UEFI" entry.
- **"Verification failed" or "Security violation":** Secure Boot is still on. Turn it off (step 3) or enroll the key.
- **Windows asks for a BitLocker recovery key:** enter the key you saved in step 3. It asks once.
- **Windows is missing from the start-up menu after an "alongside" install:** tell us in the chat. Pick "Windows Boot Manager" from the PC's boot menu key meanwhile.
