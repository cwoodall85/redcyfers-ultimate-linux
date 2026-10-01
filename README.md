# Ultimate Linux

An Arch-based distribution for power users, with Claude built in.

"Ultimate Linux" is a working name. The identity lives in `distro.conf`,
`profile/profiledef.sh` and `profile/airootfs/etc/os-release`; renaming is
a find-and-replace across those and the `ultimate-` package prefix.

## What is in it today

- **A live ISO** with a KDE Plasma desktop that logs straight in, and
  archinstall for installing to disk.
- **`ask`**, a command that puts a question about the machine to Claude.
  Claude inspects the running system through read-only tools (processes,
  systemd units and journal, packages, disks, network, hardware), says which
  it used, and gives commands for you to run. It never changes anything
  itself. Output can be piped in:

  ```
  ask why is my fan loud
  journalctl -b -p err | ask what is failing at boot
  ask --login        # stores your API key in the desktop keyring
  ```

- **Claude Code**, packaged as its native binary, with its self-updater
  off because pacman owns updates.
- **Ultimate Mail and Ultimate SSH**, packaged from snapshots of their own
  git repositories (committed work only). `build.sh` reads them from
  `~/projects/ultimate-mail` and `~/projects/ultimate-ssh`; override with
  `ULTIMATE_MAIL_SRC` / `ULTIMATE_SSH_SRC`.
- **Networking tools** (`lists/net-tools.x86_64`): net-tools, dig, mtr,
  nmap, tcpdump, Wireshark, iperf3, WireGuard, OpenVPN and more.
- **`ultimate-mcp`**, the same read-only system tools as an MCP server. It is
  registered with Claude Code at each user's first login, so `claude` can
  look at the machine too.

API keys are never written to a file. `ask` reads `ANTHROPIC_API_KEY`, then
the keyring, then an `ant auth login` profile.

## Layout

| Path | What it is |
|---|---|
| `build.sh` | Builds everything inside a throwaway Arch container. Works on any host with Podman. |
| `tools/container-build.sh` | The part that runs inside the container: makepkg, repo-add, mkarchiso. |
| `tools/test-vm.sh` | Boots the newest ISO in a libvirt VM with a Spice console. |
| `packages/` | PKGBUILDs for the distro's own repository. |
| `profile/` | The archiso profile. The first commit is Arch's `releng` profile unmodified, so `git diff` against it shows exactly what this distro changes. |
| `lists/` | Package lists installed on the live ISO **and** on every installed system (via `/etc/ultimate/archinstall.json`). |
| `tools/test-install.sh` | Unattended install in the test VM, then checks the installed system. |
| `distro.conf` | Name, URLs, default Claude model. |

## Build and test

```
./build.sh              # packages into out/repo, then the ISO into out/iso
./build.sh packages     # just the repository
./build.sh iso          # just the ISO

tools/test-vm.sh             # fresh VM "ultimate-test" on qemu:///system
tools/test-vm.sh --keep-disk # new ISO, keep what you installed
tools/test-vm.sh --destroy
```

The VM boots its disk first and falls through to the ISO while the disk is
blank, so after an install it comes up in the installed system.

## Roadmap

### Track A: the distro people install

1. **Done:** live ISO, own package repository, Claude tools, libvirt test loop.
2. **Host the repository.** Publish `out/repo` (GitHub Releases or Pages) and
   sign packages and the database with a distro GPG key. Today the ISO
   carries the repository and the installer installs from it, then removes
   the `[ultimate]` entry from the installed system (it points at a path
   only the ISO has). So installed systems get Ultimate Mail, Ultimate SSH
   and the Claude tools but **no updates to them** until the repository is
   hosted and the installer writes its public URL instead.
3. **Installed-system identity.** An `ultimate-release` package providing
   os-release, the logo and default Plasma settings, pulled in by the
   installer. Today the branding exists only on the live medium.
4. **Graphical installer.** Package Calamares, which Arch does not ship, and
   write its modules config. Until then archinstall is the installer, and it
   installs plain Arch plus whatever packages you add to its config.
5. **More Claude integration**, each read-only unless the user confirms:
   a shell keybinding that sends the last failed command and its output to
   `ask`; a Plasma widget; `ask --fix` that proposes a command and runs it
   only after you approve; an update-review step that summarises a pending
   `pacman -Syu` and Arch news before you apply it.
6. **CI.** Build the ISO on every tag with GitHub Actions and publish the
   ISO with checksums and a signature.

### The look (`packages/ultimate-theme`)

The Ultimate global theme, the default for every new user: the Ultimate Dark
colour scheme (near-black, mint-white text, mint and teal accents), Inter
and JetBrains Mono, and **Cognition**, an animated wallpaper of a thinking
network -- signals crossing a neural lattice while fragments of machine
thought (`attn = softmax(QKᵀ/√d)`, `plan → act → observe`) surface and fade.

The wallpaper also draws, as part of itself rather than as desktop widgets:
- a **system readout** down the right side -- clock, OS and kernel, uptime,
  CPU history with per-core bars, memory, network and disk -- from KDE's
  sensor service, with no boxes, over an edge-to-edge shade;
- **Claude's work** on the left when you use the Claude bar.
The network speeds up with CPU load and while Claude is thinking. The
login and lock screens use a still of the network; Konsole gets a matching
profile. `palette.py` generates the colours and the still from one palette.

### The Claude bar (`packages/ultimate-claude`)

A prompt across the top of the screen; Meta+Space focuses it. Claude
answers with the same read-only system tools as `ask`, and its steps and
answer appear over the wallpaper. By default it runs **Claude Code signed in
to your Claude subscription** (`claude -p`, with Claude Code's own tools
turned off and only the read-only `ultimate-mcp` tools allowed); an API key
works too (`CLAUDE_ENGINE=api` in `/etc/ultimate/claude.conf`). On first
login a terminal offers the sign-in (`claude auth login --claudeai`); run
`ultimate-claude-welcome` to sign in later. `ultimate-claude-bar demo` plays
a scripted run without signing in.

### Track B: from scratch (`scratch/`)

`scratch/build.sh` builds Linux From Scratch 13.1 (systemd edition, kernel
7.1.8, GCC 16.2, glibc 2.44) with jhalfs, in a rootless Podman container,
with every final-system package made into a pacman 7.1 package. It resumes
where it stopped; `REGENERATE=1` starts over. Pieces:

- `scratch/pkgmngt/` -- jhalfs's pacman recipe updated to pacman 7.1.0,
  libarchive 3.8.9, curl 8.22.0, fakeroot 1.37.1.1, zstd packages.
- `scratch/kernel/` -- the kernel config: `x86_64_defconfig` plus
  `ultimate.fragment` (systemd requirements, VM, desktop graphics and
  input, WireGuard, nftables, container namespaces). Regenerate with
  `scratch/tools/make-kernel-config.sh <version>`.
- `scratch/tools/write-jhalfs-config.py` -- jhalfs's configuration, set
  through its own kconfig library instead of the menu.

Rootless-Podman fixes it carries: the chroot binds `/dev` recursively
(a plain bind leaves `/dev/null` a regular file), jhalfs runs under a sized
pseudo-terminal, and LFS 13.1's released patches are pre-seeded because
jhalfs fetches from the development patch directory.

**Status: the base system boots.** All 86 packages build and are tracked by
pacman (kernel 7.1.8, systemd 261, glibc 2.44, GCC 16.2, pacman 7.1, GRUB
2.14). `scratch/make-image.sh` turns the build into a BIOS disk image with
our own GRUB -- no loop devices or mounts, so it works rootless -- and
`scratch/test-vm.sh` boots it in libvirt as `ultimate-src` (test login
root / ultimate). Verified: boots to a login, systemd `running` with no
failed units, DHCP, DNS and HTTP work.

Further fixes the build carries, all for current LFS against jhalfs's old
pacman recipe or for rootless Podman: curl without libpsl; the book's
OpenSSL 4 patch for the chapter 7 Python; pkgconf instead of pkg-config;
libxcrypt and --disable-logind for the chapter 7 shadow; xz packages
until zstd exists; explicit staged paths for GCC; extraction without
restoring upstream owners.

**Status: KDE Plasma runs on it.** `scratch/plan-blfs.sh` resolved the
desktop layer (Plasma 6, SDDM, Konsole, Dolphin, Kate, Ark, Spectacle, with
required and recommended dependencies) against BLFS 13.1 into 534 build
steps, and `scratch/blfs-build.sh` built all of them in the chroot. BLFS
puts KDE under /opt/kf6 and Qt under /opt/qt6. `make-image.sh` now adds a
desktop user (test only: ultimate / ultimate) and hands networking to
NetworkManager. Verified in the VM: SDDM login, a Plasma (Wayland) session.

The desktop layer is **not** pacman-managed: the BLFS tools install
directly. Book problems worked around (worth reporting upstream):
tesseract lists Leptonica with role="requrired", so it was never planned;
accountsservice 26.27.3 needs json-c, which its page omits; json-c's test
CMake bump is wrong for 0.19. Hand-added steps live in `scratch/blfs/extra`,
per-package fixes in `scratch/blfs/fixes`.

**Status: the Ultimate layer.** `scratch/ultimate-layer.sh` installs the
distro's own packages (the look, the Claude bar, Claude Code) on the
from-source system. Stage 2 (`STAGE=2 scratch/blfs-build.sh`,
`scratch/blfs/targets-2.conf` plus `scratch/blfs/extra-2`) builds what
Ultimate Mail and Ultimate SSH need (WebKitGTK, libadwaita, VTE) and the
networking tools.

**Status: the installer works.** The image boots under BIOS and UEFI (an
MBR disk with an EFI system partition; our GRUB for both firmwares). It
carries `ultimate-install` (`scratch/installer/`), which puts the running
system on a disk: GPT with BIOS boot, EFI and root partitions, a new
account, host name, machine id and SSH keys, and GRUB for both firmwares.
Stage 3 builds what it needs (dosfstools, efibootmgr, gptfdisk, sudo,
GRUB for UEFI) and rebuilds the kernel with USB storage built in, so the
image can boot from a stick. Test it with
`scratch/test-vm.sh --uefi --target-disk`, then `--installed`. Verified: the
image boots under BIOS and UEFI; an unattended install boots under both, to
the new account's Plasma session. Every HD Audio codec driver is built, so
sound works (PipeWire). Ultimate SSH is the terminal the distro opens (the
first-login Claude sign-in, the installer), see-through like the Konsole
profile.

**Status: real hardware.** Stage 4 (`scratch/blfs/extra-4`) installs
linux-firmware (zstd), Sound Open Firmware, wireless-regdb, cryptsetup, and
CPU microcode images that GRUB loads as a microcode-only initrd (there is
no initramfs). The kernel config adds whole driver families
(`scratch/kernel/all-of.list`, applied by `scratch/kernel/enable-families.sh`):
Wi-Fi, laptop DSP audio, touchpads, USB4, plus everything Chris's desktop
loads. `scratch/tools/check-host-drivers.sh`, run on a machine's current OS,
lists any driver it uses that our kernel lacks
(`docs/hardware-chris-desktop.md` is the first report).

**Status: tested automatically.** `scratch/test-image.sh` boots the image
in KVM, checks it over SSH, starts a desktop session, updates a package with
`pacman -Syu`, installs to a second disk, and boots that under UEFI and BIOS
(34 checks; `ci-build.sh`'s `test` step).

**Status: the desktop layer is pacman-managed.** `scratch/pkg/` attributes
every file the BLFS stages installed to the build that wrote it and makes
one pacman package per build step (about 600), registered in the system's
database and published as the `ultimate-desktop` repository. Updates are
`pacman -Syu`, not reinstalls. `ci-build.sh`'s `desktop` step runs it.

**Claude bar plug-ins.** Packages add read-only tools for the Claude bar,
`ask` and `ultimate-mcp` by dropping a Python file into
`/usr/lib/ultimate/mcp.d/` (contract in its README).

**Secure Boot and dual boot.** `scratch/secureboot/sign.sh` signs GRUB and
the kernel for shim (Secure Boot stays on; the owner enrolls the Ultimate
Linux key once). `ultimate-install` (package `ultimate-boot`) installs to a
whole disk, alongside another system (free space, the shared EFI partition,
its own firmware entry, other systems in its menu), or over an earlier
install; `ultimate-migrate` brings a dual-booted Fedora's setup over. The
steps for Chris's desktop are in `docs/dual-boot.md`.

Next: hosting the repositories and package signing (with the home-base
session).

#### Linux From Scratch as a learning track

Linux From Scratch (LFS) in a separate VM, alongside Track A. It teaches how
the toolchain, kernel, init and userland fit together, and it is the path to
owning more of the stack later: a custom kernel config, then your own
builds of the packages you most want to control. A full from-scratch base
as the shipped distro would mean patching security holes across thousands
of packages alone, which is the usual reason one-person distros die, so the
shipped base stays Arch.

## Before a public release

- **Arch trademarks.** Do not use the Arch logo or name the distro "Arch
  anything". "Arch-based" is fine. The boot menus here already say Ultimate
  Linux.
- **Claude Code licensing.** Claude Code is proprietary. Check Anthropic's
  terms on redistributing the binary before shipping it in a public ISO. The
  alternative is a first-boot step that installs it with Anthropic's own
  installer.
- **Signing.** `SigLevel = Optional TrustAll` on the local repository is for
  builds only. The public repository must be signed.
- **Ultimate Mail and Ultimate SSH are in the ISO.** A public ISO publishes
  them, so scrub both repositories (history included) for secrets, personal
  hosts and settings first. `ops/morning-brief` is already left out of the
  Mail package.
