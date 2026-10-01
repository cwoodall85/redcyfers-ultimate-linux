#!/bin/bash
# Runs INSIDE the Arch build container (see ../build.sh). Builds every
# package under /src/packages into the local repository at /ultimate-repo,
# then builds the ISO from /src/profile into /src/out/iso.
set -euo pipefail
what=${1:-all}

pacman -Syu --noconfirm --needed base-devel archiso git sudo npm python-installer libcap >/dev/null
# The keyring package updates above, but its hook that loads the new keys
# needs systemd and fails in a container ("command failed to execute
# correctly"), so packages from newer packagers fail signature checks.
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux >/dev/null
id builder >/dev/null 2>&1 || useradd -m builder

if [[ $what == all || $what == packages ]]; then
  id builder >/dev/null 2>&1 || useradd -m builder
  echo 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/builder
  rm -rf /tmp/pkgbuild && cp -r /src/packages /tmp/pkgbuild
  for app in ultimate-mail ultimate-ssh; do
    cp "/src/out/sources/$app.tar.gz" "/tmp/pkgbuild/$app/"
    cp "/src/out/sources/$app.VERSION" "/tmp/pkgbuild/$app/VERSION"
  done
  chown -R builder /tmp/pkgbuild
  install -d -o builder /ultimate-repo
  # Start empty so superseded builds never reach the repository or the ISO.
  rm -f /ultimate-repo/*.pkg.tar.zst
  # Order matters: ultimate-claude depends on python-anthropic, and makepkg
  # installs build/check deps from repos only, so a dependency must be in
  # the local repo -- and the repo known to pacman -- before its dependents.
  # With --nodeps, makepkg installs nothing itself; the theme generates its
  # images and colours at build time and needs these.
  pacman -S --noconfirm --needed python-pillow fontconfig ttf-dejavu librsvg >/dev/null
  for pkg in python-anthropic python-imapclient claude-code ultimate-claude ultimate-mail ultimate-ssh ultimate-theme ultimate-boot; do
    echo "== building $pkg"
    (cd /tmp/pkgbuild/$pkg && sudo -u builder PKGDEST=/ultimate-repo makepkg -f --noconfirm --nodeps)
  done
  rm -f /ultimate-repo/ultimate.db* /ultimate-repo/ultimate.files*
  repo-add -q /ultimate-repo/ultimate.db.tar.gz /ultimate-repo/*.pkg.tar.zst
  ls -1 /ultimate-repo
fi

if [[ $what == all || $what == iso ]]; then
  # mkarchiso run as root mounts a fresh /dev for its chroot, which rootless
  # Podman forbids. Run as an ordinary user it uses its own supported
  # unprivileged mode instead (pacstrap -N, user namespaces), which only
  # needs a subordinate id range inside the container's own 65536 ids.
  id builder >/dev/null 2>&1 || useradd -m builder
  # The container image drops file capabilities; newuidmap and newgidmap
  # need theirs back for an unprivileged user to map a namespace.
  setcap cap_setuid+ep /usr/bin/newuidmap
  setcap cap_setgid+ep /usr/bin/newgidmap
  echo 'builder:2000:60000' > /etc/subuid
  echo 'builder:2000:60000' > /etc/subgid
  # The pacman cache volume is shared between builds. A local package
  # rebuilt under the same version would be found there first and fail its
  # checksum against the new repository database, so drop those copies.
  for f in /ultimate-repo/*.pkg.tar.zst; do rm -f "/var/cache/pacman/pkg/${f##*/}"; done
  # A failed run can leave a package in the cache without its .sig; pacman
  # then trusts the cached file and fails "missing required signature".
  for f in /var/cache/pacman/pkg/*.pkg.tar.zst; do
    [[ -e $f.sig ]] || rm -f "$f"
  done
  rm -rf /work /tmp/iso && install -d -o builder /work /tmp/iso
  rm -rf /tmp/profile && cp -r /src/profile /tmp/profile
  # Package lists in lists/ go onto the live ISO and into the installer
  # config, so what the live system has and what an install gets can't drift.
  python3 /src/tools/apply-lists.py /src/lists /tmp/profile
  # Carry the distro's own repository on the ISO, and point the live
  # system's pacman at it. archinstall installs from the live pacman
  # config, so an install gets these packages with no network repository.
  install -d /tmp/profile/airootfs/opt/ultimate-repo
  cp /ultimate-repo/ultimate.db* /ultimate-repo/ultimate.files* /ultimate-repo/*.pkg.tar.zst \
    /tmp/profile/airootfs/opt/ultimate-repo/
  sed 's|^Server = file:///ultimate-repo$|Server = file:///opt/ultimate-repo|' \
    /tmp/profile/pacman.conf > /tmp/profile/airootfs/etc/pacman.conf
  # Download and signature-check every package as real root first. In
  # mkarchiso's unprivileged mode pacman cannot use the root-owned keyring,
  # so any package not already cached fails "missing required signature".
  grep -hv '^\s*\(#\|$\)' /tmp/profile/packages.x86_64 | sort -u |
    xargs pacman --config /tmp/profile/pacman.conf -Syw --noconfirm >/dev/null
  # Every package the ISO needs is now in the cache and verified. GnuPG
  # cannot run inside mkarchiso's user namespace ("GPGME error:
  # Inappropriate ioctl for device"), so the unprivileged install reuses
  # those verified files without checking again. This changes only the
  # build copy's pacman.conf; the live system's /etc/pacman.conf, written
  # above, keeps full signature checking.
  sed -i 's/^SigLevel .*/SigLevel = Never/' /tmp/profile/pacman.conf
  chown -R builder /tmp/profile
  sudo -u builder mkarchiso -v -w /work -o /tmp/iso /tmp/profile
  # Remove first rather than overwrite: while a VM uses the ISO, libvirt
  # hands the file to the qemu user, and only the directory owner can
  # replace it.
  for f in /tmp/iso/*.iso; do rm -f "/src/out/iso/${f##*/}"; cp "$f" /src/out/iso/; done
  ls -lh /src/out/iso
fi
