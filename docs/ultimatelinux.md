# Ultimate Linux — project brief

A brief for another Claude session (redcyfer) joining this project. It says
what exists, what is in progress, and how to build and test it. Written
2026-09-29 (updated the same afternoon) from the machine where the work happens (Chris's Fedora 44 box,
`~/projects/ultimate-linux`).

## What it is

Chris's own Linux distribution, for power users, with Claude built in, aimed
at a **public release**. "Ultimate Linux" is a working name, matching his
other apps (Ultimate Mail, Ultimate SSH, Ultimate Chat). The identity lives
in `distro.conf`, `profile/profiledef.sh` and `profile/airootfs/etc/os-release`.

There are two tracks in one repository:

| Track | What | State |
|---|---|---|
| **A: Arch-based** (repo root) | archiso live ISO with KDE Plasma, our own pacman repository, archinstall-based install | Works end to end: ISO boots, installs to disk, installed system boots to SDDM and Plasma |
| **B: from source** (`scratch/`) | Linux From Scratch 13.1 (systemd) + BLFS 13.1 desktop, our own kernel config and GRUB, pacman as package manager | Boots to KDE Plasma 6 with the Ultimate layer; installer and UEFI boot being finished |

Chris is most interested in track B ("I wanted to have my own linux distro").
Track A is the practical base; track B is where the control is.

## What makes it "Ultimate" (the Ultimate layer)

Shared by both tracks, built as pacman packages from `packages/`:

- **`ultimate-theme`**: the Ultimate Dark colour scheme (near-black,
  mint-white text, mint and teal accents), Inter and JetBrains Mono, and
  **Cognition**, an animated wallpaper. It shows a neural lattice with
  signals crossing it, while fragments of "machine thought"
  (`attn = softmax(QKᵀ/√d)`, `plan → act → observe`) fade in and out. Chris
  rejected a Matrix-rain look as dated. The wallpaper also draws a system
  readout on the right: clock, OS and kernel, uptime, CPU history with
  per-core bars, memory, network and disk. Chris said desktop widgets
  blocked the view, so there are no widgets. `palette.py` generates every
  colour from one palette.
- **`ultimate-claude`**:
  - **The Claude bar.** A panel across the top of the screen, focused with
    Meta+Space. Claude's steps and answer appear translucent over the
    wallpaper on the left.
  - **`ask`.** The same thing on the command line (`ask why is my fan loud`,
    `journalctl -b -p err | ask what is failing`).
  - **`ultimate-mcp`.** The read-only system tools as an MCP server:
    processes, systemd units and the journal, packages, disks, network and
    hardware. It is a self-contained JSON-RPC stdio server with no MCP SDK,
    because the SDK's 2.x rename broke it.
  - **Engine.** By default it runs **Claude Code signed in to Chris's Claude
    subscription** (OAuth), not an API key, so no key is needed. Claude
    Code's own tools are off and only our read-only tools are allowed:
    ```
    claude -p "<question>" --output-format stream-json --verbose --tools "" \
      --strict-mcp-config --mcp-config <ultimate-mcp json> \
      --allowedTools mcp__ultimate-system --append-system-prompt …
    ```
    Setting `CLAUDE_ENGINE=api` in `/etc/ultimate/claude.conf` uses an API
    key instead.
  - **First-login sign-in.** A terminal offers
    `claude auth login --claudeai` (`ultimate-claude-welcome`).
  - **Rule:** Claude never changes the system itself. It gives commands for
    the user to run.
- **`claude-code`**: the native Claude Code binary, with its self-updater
  off because pacman owns updates.
- **`ultimate-mail`, `ultimate-ssh`**: Chris's GTK4 apps, packaged from
  `git archive HEAD` snapshots of `~/projects/ultimate-mail` and
  `~/projects/ultimate-ssh`. They need WebKitGTK 6.0, libadwaita and VTE
  (GTK 4).
- **Networking tools** (`lists/net-tools.x86_64`, 57 packages): dig, mtr,
  nmap, tcpdump, Wireshark, iperf3, WireGuard, OpenVPN and more. Chris wants
  these in every install.

## Repository layout

```
build.sh                 Track A: packages -> out/repo, ISO -> out/iso (podman, Arch container)
distro.conf              name, URLs, default Claude model
packages/                PKGBUILDs: ultimate-claude, ultimate-theme, ultimate-mail, ultimate-ssh,
                         claude-code, python-anthropic, python-imapclient
profile/                 archiso profile (first commit = Arch releng, so git diff shows our changes)
lists/                   package lists for the live ISO and every installed system
tools/                   test-vm.sh (libvirt), test-install.sh (unattended archinstall + checks),
                         vm-exec.py (commands in the VM via the QEMU guest agent)
scratch/                 Track B, from source
  build.sh               LFS 13.1 base via jhalfs, every package made into a pacman 7.1 package
  pkgmngt/               jhalfs's pacman recipe, updated to pacman 7.1.0
  kernel/                ultimate.fragment + generated config-7.1.8 (make-kernel-config.sh)
  plan-blfs.sh           resolve blfs/targets[-N].conf against BLFS 13.1 into build scripts
  blfs-build.sh          run those scripts in the chroot (STAGE=N), resumable
  blfs/driver.sh         the in-container driver; fetch.py pre-fetches sources
  blfs/targets*.conf     what each stage builds
  blfs/extra[-N]/        hand-written steps the planner misses
  blfs/fixes/<pkg>.sh    per-package patches to the generated scripts
  ultimate-layer.sh      install the Ultimate packages into the from-source system
  make-image.sh          build tree -> out/ultimate-src.qcow2 (BIOS + UEFI, no loop devices)
  installer/             ultimate-install, its desktop launcher, polkit wheel rule
  test-vm.sh             boot the image in libvirt as "ultimate-src"
```

**The code is only on Chris's machine.** There is no git remote yet (the
repo has about 30 commits). Publishing it to GitHub, and scrubbing Ultimate
Mail and Ultimate SSH first, is an open decision.

## How to build

### Host requirements

- Linux with **rootless Podman** and **libvirt/QEMU**. Everything builds
  inside throwaway `archlinux:latest` containers, so the host distro doesn't
  matter.
- For rootless mkarchiso and the chroot builds:
  - `newuidmap`/`newgidmap` with setcap;
  - a subuid/subgid range for the build user;
  - containers run with `--privileged --security-opt label=disable` (not `:z`).
- Disk: roughly 100 GB free. Memory: 32 GB+; see the WebKitGTK note below.
- Podman volumes used by track B:
  - `ultimate-lfs-build`: the system being built, and later the image source;
  - `ultimate-lfs-sources`: the source tarballs;
  - `ultimate-blfs-plan`: the BLFS tools and generated scripts;
  - `ultimate-pacman-cache`: the pacman package cache.

### Track A: the Arch-based ISO

```
./build.sh              # packages into out/repo, then the ISO into out/iso
tools/test-vm.sh        # boot it in libvirt ("ultimate-test")
tools/test-install.sh   # unattended install in the VM + checks
```

### Track B: from source, in order

```
scratch/build.sh                         # 1. LFS base, hours; resumes where it stopped
scratch/plan-blfs.sh                     # 2. plan the desktop (534 steps)
scratch/blfs-build.sh                    # 3. build Qt6, KF6, Plasma 6, SDDM, apps (many hours)
STAGE=2 scratch/plan-blfs.sh             # 4. plan stage 2: WebKitGTK, libadwaita, VTE, net tools
STAGE=2 scratch/blfs-build.sh            #    ...and build it
STAGE=3 scratch/plan-blfs.sh             # 5. stage 3: dosfstools, efivar, efibootmgr, gptfdisk,
STAGE=3 scratch/blfs-build.sh            #    sudo; kernel rebuild; GRUB for UEFI
./build.sh packages                      # 6. the Ultimate packages
scratch/ultimate-layer.sh                # 7. install them into the from-source system
TEST_SSH_KEY="$(cat ~/.ssh/id_ed25519.pub)" scratch/make-image.sh   # 8. disk image
scratch/test-vm.sh [--uefi] [--target-disk] [--installed]           # 9. test
```

`TEST_SSH_KEY` lets root in over SSH by that key, which is how automated
tests get into the from-source VM, since it has no guest agent. Never set it
for an image you hand out.

Test logins (test images only):
- root / ultimate;
- desktop user ultimate / ultimate, which the installer deletes.

### Installing (track B)

Boot the image, from USB or in a VM, then run `ultimate-install` as root,
or use "Install Ultimate Linux" on the desktop. It:
1. makes a GPT (BIOS boot, EFI, root) on the chosen disk;
2. copies the running system;
3. creates your account, host name, machine id and SSH host keys;
4. installs GRUB for BIOS and UEFI.

For unattended runs, set `UI_DISK`, `UI_USER`, `UI_FULLNAME`, `UI_PASSWORD`,
`UI_ROOT_PASSWORD`, `UI_HOSTNAME` and `UI_YES=1`.

## Current status (2026-09-29)

**Done and verified:**
- Track A: ISO → install → SDDM and Plasma, net tools and apps present,
  `pacman -Sy` clean.
- Track B: our kernel (7.1.8) and GRUB boot to Plasma 6 with the Ultimate
  layer working:
  - Cognition wallpaper and system readout;
  - Ultimate Dark;
  - the Claude bar, which answers "not signed in" until you sign in;
  - the welcome terminal;
  - Claude Code 2.1.283.
- On Chris's desktop, the bar through Claude Code on his Max subscription
  answers in about 5 s using the system tools.

- **Installer and dual-firmware boot, verified 2026-09-29:**
  - the image boots under BIOS and UEFI;
  - `ultimate-install` puts it on a second disk, which boots under both
    firmwares to the new account's Plasma session;
  - Ultimate Mail, Ultimate SSH and all the net tools run;
  - sound works (every HD Audio codec driver built; PipeWire).
- **Ultimate SSH is the distro's terminal.** The first-login Claude sign-in
  and the installers open in it (`ultimate-ssh --run`). It is see-through
  like the Konsole profile (Settings → Opacity, default 92%).

**Next:**
1. Test on real hardware from a USB stick. The from-source track still
   lacks `linux-firmware` (GPUs, Wi-Fi) and Sound Open Firmware (newer
   Intel laptop audio).
2. Convert the desktop layer to pacman packages. Today only the LFS base is
   pacman-managed; BLFS installs directly.
3. Host the package repository and updates (see below).

## Updates and hosting

Updates are package upgrades (`pacman -Syu`), not reinstalls.

- **The repositories:** `scratch/repo/make-repo.sh` builds three signed
  repositories (default `/mnt/storage/ultimate-repo`, set `OUT=`):
  - `ultimate`: our packages plus the native builds;
  - `ultimate-desktop`: the desktop layer;
  - `ultimate-base`: the LFS base.

  Each name is in exactly one repository; the last layer installed wins.
  `REPORT.txt` compares the repositories with this machine's installed
  packages. Packages that may not be redistributed (`EXCLUDE`) are never
  published, and a package carrying a private key stops the build.
- **Signing:** an OpenPGP ed25519 key. The primary key (certify-only) is
  `C5CD9FC604784D0AF203F7A65E6B98FFFE9B6BA4`, meant to live offline; a separate
  subkey signs. `ultimate-keyring` ships the public key; `ultimate-mirrorlist`
  ships the server list; pacman's own `pacman.conf` lists the three
  repositories with `SigLevel = Required DatabaseRequired`.
- **Hosting:** `scratch/repo/publish.sh` copies the tree to the hosting
  server (rsync over SSH, `DONE` written last), which syncs it to object
  storage behind a CDN. The public mirror is
  `https://pkg.redcyfer.com/$repo/os/$arch`.
- **Releases** (disk images) are at `https://dl.redcyfer.com/releases/`.

## Traps worth knowing

- **Build-container traps:**
  - The chroot needs `/dev` bound recursively. Otherwise `/dev/null` becomes
    a regular file, and Claude Code's Bun binary aborts.
  - GnuPG can't run in mkarchiso's user namespace. Packages are
    pre-downloaded as root, and `SigLevel=Never` is set only in the build
    copy of pacman.conf.
  - Extract with `tar --no-same-owner`: rootless Podman can't map upstream
    owners.
- **BLFS tools:**
  - Editing the tracking file changes nothing until `packages.xml` is
    regenerated.
  - Book bugs worked around: tesseract lists Leptonica as
    `role="requrired"`; accountsservice needs json-c, which its page omits;
    json-c's test CMake bump is wrong for 0.19.
- **Layout:** KDE is in `/opt/kf6` and Qt in `/opt/qt6`, so SDDM and
  anything launched outside a login shell need `QML2_IMPORT_PATH`,
  `QT_PLUGIN_PATH` and `XDG_DATA_DIRS` set.
- **Plasma and QML:**
  - A panel needs `Plasmoid.status = AcceptingInputStatus` to take keyboard
    focus.
  - 60 fps QML animations on software GL cost about 200% CPU. All wallpaper
    motion is driven by one timer, capped at 15 fps (6 fps on llvmpipe).
- **Claude engine:** it never reads the Python keyring in auto mode, because
  that pops a KDE Wallet dialog that blocks the run.
- **libvirt:** never `virsh undefine --remove-all-storage`, which deletes the
  ISO or image. `test-vm.sh` uses `--nvram` only.

## Before a public release

- Don't use the Arch name or logo. "Arch-based" is fine.
- Check Anthropic's terms on redistributing the Claude Code binary. The
  alternative is installing it at first boot with Anthropic's installer.
- Sign the public repository and its database. The build uses
  `SigLevel = Optional TrustAll`.
- Scrub Ultimate Mail and Ultimate SSH, history included, of secrets and
  personal hosts before they ship in a public ISO.
- Remove test passwords and test SSH access. Neither is in images built
  without `TEST_SSH_KEY`, but the test user is.
- Real hardware needs `linux-firmware` for i915, amdgpu and nouveau. The
  kernel has these drivers as modules but the from-source track doesn't
  ship the firmware yet.
