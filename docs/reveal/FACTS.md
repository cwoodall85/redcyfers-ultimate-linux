# Ultimate Linux — facts for the reveal

Gathered 2026-10-01 on Chris's desktop, which runs Ultimate Linux (track B) on
real hardware. All numbers were measured on this machine or read from the
repository. Nothing here is a plan unless it says so.

## What it runs (track B, "from source")

| Part | Version / detail |
|---|---|
| Base | Linux From Scratch **13.1** (systemd variant), built with jhalfs |
| Kernel | **linux-ultimate 7.1.8** (our package 7.1.8.4), our own config: x86_64 defconfig plus `scratch/kernel/ultimate.fragment` |
| Init | **systemd 261.2** |
| Toolchain | **GCC 16.2.0**, **glibc 2.44**, **binutils 2.47** |
| Desktop | **KDE Plasma 6.7.4** on Wayland (KWin), **KDE Frameworks 6.29.0**, **Qt 6.11.2**; Mesa 26.1.7 |
| Package manager | **pacman 7.1.0** (our build, with gpgme for signed repositories) |
| Display manager | SDDM, themed |
| Boot | GRUB 2.14 behind Microsoft-signed shim 16.1; **Secure Boot on**, kernel and GRUB signed with our own MOK key |
| Installed packages (Chris's desktop) | **746** |

Kernel config highlights:
- Full preemption (`PREEMPT_DYNAMIC`, lazy preemption), `HZ=1000`.
- EFI stub. ext4 and VFAT built in. Btrfs, XFS, exFAT, NTFS3, NFS, CIFS, squashfs and overlayfs as modules.
- GPU drivers amdgpu, i915, xe and nouveau as modules. `linux-firmware` (20260916) shipped as a package.
- Every HD Audio codec driver enabled. The first build had none, so there was no sound.
- KVM (AMD and Intel), virtio, nftables, cgroups v2 with BPF, seccomp, user namespaces.
- Not yet: Landlock (see war stories).

### Package repositories

Three signed pacman repositories, built by `scratch/repo/make-repo.sh`:

| Repository | Packages | Size | Contents |
|---|---|---|---|
| `ultimate-base` | 79 | 651 MB | the LFS base system |
| `ultimate-desktop` | 604 | 4.4 GB | the BLFS desktop layer (Plasma, Qt, Mesa, firmware…) |
| `ultimate` | 60 | 613 MB | our own packages and native builds |
| **Total** | **743** | **~5.7 GB** | |

The repositories in `/mnt/storage/ultimate-repo` were built 2026-09-30 13:30
and are behind the desktop. Newer builds of ultimate-claude (0.11.2),
ultimate-theme (0.6.0), ultimate-browser, qt6-webengine and kdeconnect exist
as package files but haven't been added yet.

### Image

- `scratch/out/ultimate-src.qcow2`: a 19.3 GiB virtual disk with 12.9 GiB used. It has an MBR layout with an EFI partition and a root partition.
- It boots under both BIOS and UEFI.
- `make-image.sh --usb` builds the same system for a 16 GB USB stick (it fits a 14.6 GB stick).
- There is no ISO for track B. Only track A (Arch-based) makes ISOs.

## How it was built

**Two tracks.**
- **A — Arch-based (archiso):** an ISO, archinstall, and our packages layered on Arch. This was the first, quick path and proved the Claude integration.
- **B — from source:** what Chris runs now. It's the only track with a pipeline going forward.

**Track B stages** (all in rootless Podman):
1. **LFS 13.1 base** via jhalfs. Each package is turned into a pacman package (86 packages).
2. **BLFS stage 1:** the KDE Plasma desktop (~534 packages).
3. **BLFS stage 2:** WebKitGTK, libadwaita, VTE and the network tools (~143 packages).
4. **Stage 3:** installer tools, a kernel rebuild, and GRUB for UEFI.
5. **Stage 4:** firmware, microcode, drivers, DejaVu fonts and cryptsetup for real hardware.
6. **Stage 5:** Flatpak and ostree. Desktop apps come from Flathub.
7. **Desktop layer → pacman packages:** about 601 packages, attributed to their build by file ctime windows.
8. **Native packages:** our own PKGBUILDs (`packages/`), built with makepkg on the system itself.

**Measured build time** on a Ryzen 9 9950X (16 cores / 32 threads, 91 GB RAM), `-j32` (WebKitGTK capped at `-j12`):

| Part | Packages | Hours |
|---|---|---|
| LFS 13.1 base | 86 | 0.75 |
| Stage 1: Plasma desktop | ~534 | 2.16 |
| Stage 2: WebKitGTK, libadwaita, VTE, net tools | ~143 | 1.09 |
| Stage 3: installer, kernel, UEFI GRUB | ~9 | 0.06 |
| **Total** | **828** | **4.06** |

- Three packages take 32% of the time: WebKitGTK 52 min, Rust 13, Qt6 12.
- The 752 packages under 30 s take 28%, mostly single-threaded `configure`. More cores barely help.
- Downloading sources (~640 MB) isn't included.

**Signing.**
- The repositories and their databases are signed with an OpenPGP **ed25519** key.
- The primary key is certify-only (`C5CD9FC604784D0AF203F7A65E6B98FFFE9B6BA4`) and is to be moved offline.
- A separate signing subkey signs the packages.
- `ultimate-keyring` ships the public key; pacman uses `SigLevel = Required DatabaseRequired`.
- Secure Boot uses a separate MOK key, enrolled on Chris's machine.

**The update repository.**
- `pacman -Syu` pulls from the public mirror `https://pkg.redcyfer.com/$repo/os/$arch` (object storage behind a CDN). Updates go live about a minute after publishing.

**Installer.** `ultimate-install` (package `ultimate-boot`) has three modes:
- whole disk;
- alongside another OS (dual boot);
- reinstall.

`ultimate-migrate` copies settings over from an existing Linux install. Chris's
desktop was installed alongside Fedora this way on 2026-09-29, with Secure
Boot on. The test suite (`scratch/test-image.sh`, 51 checks) covers:
- BIOS and UEFI boot;
- install;
- pacman updates;
- dual boot with Secure Boot.

## Home-brewed apps

**ultimate-claude** (0.11.2). Claude built into the desktop.
- **Claude bar** (top panel, Meta+Space): ask a question; the answer and Claude's tool steps appear on the wallpaper, with history kept (`~/.local/state/ultimate/claude-history.jsonl`).
- **`ask`**: the same from any terminal, and it takes piped input (`journalctl -b -p err | ask what is failing`).
- **`ultimate-mcp`**: a FastMCP server of read-only system tools (processes, disks, sensors, network, logs, packages…). It loads plug-in tool sets from `/usr/lib/ultimate/mcp.d/`.
- It runs through Claude Code on the user's own Claude subscription. It uses `claude -p` with only our MCP tools allowed, so no API key is needed; API keys also work.
- **Read-only rule:** the bar's tools only look. Anything that changes the system needs a per-task approval: the first "Allow" covers that task.
- **Voice:** push-to-talk with whisper.cpp for speech-to-text and Piper for answers read aloud. Bluetooth headsets switch to their mic profile automatically.
- The bar reports to Ultimate Chat, so approvals can come from a phone.

**ultimate-mail**. A GTK4 mail client.
- Works with IMAP, Gmail and Office 365 (OAuth).
- Has threaded conversations, rules, a calendar (mirrors the account calendars), a built-in terminal and Chat view, and an MCP server so Claude can read and triage mail.
- Has an offline demo mailbox (`um/demo.py`), which is what the screenshots use.

**ultimate-ssh**. The distro's terminal and SSH manager (VTE).
- It keeps its own copy of the host list and never edits `~/.ssh/config`.
- It has host groups, search, split panes, broadcast input, a file explorer and a live status line (CPU, memory, disk, network).
- It can be see-through, and it bridges to Chat.
- The first-login Claude sign-in and the installers open in it.

**ultimate-browser** (0.3.6). A QtWebEngine browser (Qt 6.11.2 WebEngine, built here).
- Has workspaces with separate cookie profiles, vertical tabs, saved logins, and a Claude side panel with browser tools.
- A second launch hands its links to the running window.
- Installed on Chris's desktop since 2026-09-30. Tab sync is planned, not built.

**ultimate-theme** (0.6.0): the look.
- **Ultimate Dark** colour scheme.
- **Cognition** wallpaper, written in QML: a brain in profile drawn as a living network, with model-code fragments drifting past. It turns coral while Claude is working.
- Six desktop widgets: clock, CPU, memory, network, disk, and Claude's answers.
- The look-and-feel package, SDDM greeter theme and Plymouth boot splash.
- All motion runs off one timer, capped to keep CPU low.

**ultimate-boot** (1.5.2). The installer (`ultimate-install`), `ultimate-migrate`, and `ultimate-update-grub` with its pacman hook (it finds other OSes such as Fedora). Plus the Secure Boot pieces (`ultimate-secureboot`: shim and signed GRUB).

**Also packaged here:**
- `ultimate-keyring` and `ultimate-mirrorlist`;
- native builds of KDE Connect 26.04.3 (with libei), Podman, QEMU and libvirt, GitHub CLI, AWS CLI, fastfetch (our layout and logo), whisper.cpp and Piper;
- our pacman build.

**Ultimate Chat** (chat.redcyfer.com) is Chris's agent inbox, on the server side. The desktop reaches it through Ultimate Mail's Chat view and the Claude bar.

## War stories

1. **The pacman fork deadlock.**
   - After `https` downloads, pacman would freeze forever while running `ldconfig` or an install script.
   - Cause: curl's threaded DNS resolver had left threads behind in the root process. The `fork()` for the scriptlet copied a locked mutex and waited on it (a futex) forever.
   - Fix: pacman 7's `DownloadUser = alpm`, so downloads happen in a separate unprivileged process.
   - Our systemd has no `systemd-sysusers`, so we wrote `ultimate-sysusers` to create the `alpm` user.
2. **No Landlock.**
   - pacman 7 sandboxes its downloader with Landlock. Our kernel config didn't enable `CONFIG_SECURITY_LANDLOCK`, so pacman refused to download anything.
   - Workaround: `DisableSandboxFilesystem` until the kernel is rebuilt with it (still to do).
   - Before all that, pacman had been built without gpgme. So *any* signed repository broke every pacman command until we rebuilt it.
3. **`/dev` and Bun.**
   - In the rootless build container the chroot's `/dev` was a plain bind mount. `/dev/null` ended up as a regular file.
   - `configure` scripts quietly produced corrupt results, and Claude Code's Bun binary aborted at start.
   - Fix: bind `/dev` recursively (`--rbind`).
4. **200% CPU for a wallpaper.**
   - The first Cognition wallpaper ran its QML animations at 60 fps. On software GL that cost about two full cores, doing nothing.
   - Now one timer drives all motion: 15 fps, 6 fps on llvmpipe, full resolution only with hardware GL.
   - It costs about a third of one core on a 3440×1440 screen while Claude is thinking.
5. **No sound, then a dead headset mic.**
   - The first from-source kernel had no HD Audio codec drivers, so it had no sound at all. The kernel config now enables every codec.
   - Later, a Bluetooth headset's mic sent silence in the mSBC profile, on an adapter without eSCO. Voice now uses CVSD, chimes only when real audio arrives, and resets the link once if it doesn't.
6. **Secure Boot on real hardware.**
   - The MokManager screen (where you confirm a new Secure Boot key) appears before GRUB with a 10-second timeout. Chris's Bluetooth keyboard isn't alive yet at that point.
   - The first enrollment missed. It took a wired keyboard.
