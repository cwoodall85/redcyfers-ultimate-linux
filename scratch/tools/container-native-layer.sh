#!/bin/bash
# Runs INSIDE a container (see ../native-layer.sh). Installs the natively
# built packages named in /work/native-packages.txt into the from-source
# system at /b, through ITS pacman database. They were built on Ultimate
# Linux against this same system, so they fit it; dependency checks are off
# (-dd) as for the Ultimate layer, and so are hooks and scriptlets (none of
# these packages has a scriptlet; their hooks' work is done below).
set -euo pipefail
R=/b
# The archlinux image's pacman.conf skips man pages, docs and translations
# (NoExtract, to keep containers small); here that would strip them from
# the system being built. This container is thrown away: drop the lines.
sed -i '/^NoExtract/d' /etc/pacman.conf

pick() {  # newest file of package $1 in /native, /extra, /extra/native-virt
  local f
  f=$(ls /native/"$1"-[0-9]*.pkg.tar.* /extra/"$1"-[0-9]*.pkg.tar.* /extra/native-virt/"$1"-[0-9]*.pkg.tar.* 2>/dev/null |
      awk -F/ '{print $NF "\t" $0}' | sort -V | tail -1 | cut -f2)
  [[ -n $f ]] || { echo "no package file for $1" >&2; return 1; }
  echo "$f"
}
pkgs=()
while read -r n; do
  [[ -z $n || $n == \#* ]] && continue
  pkgs+=("$(pick "$n")")
done < /work/native-packages.txt
printf '  %s\n' "${pkgs[@]##*/}"

mkdir -p /tmp/nohooks
# The jhalfs-built kernel ("kernel", vmlinuz-*-lfs-*) has none of the
# netfilter families Podman's and libvirt's networks need; linux-ultimate
# replaces it, so the image carries one kernel.
if pacman --root $R --dbpath $R/var/lib/pacman -Q kernel >/dev/null 2>&1; then
  pacman --root $R --dbpath $R/var/lib/pacman --hookdir /tmp/nohooks --noscriptlet --noconfirm -Rdd kernel
fi
pacman --root $R --dbpath $R/var/lib/pacman --cachedir /tmp \
  --hookdir /tmp/nohooks --noscriptlet --noconfirm -Udd "${pkgs[@]}"

mountpoint -q $R/dev || mount --rbind /dev $R/dev
mountpoint -q $R/proc || mount -t proc proc $R/proc
mountpoint -q $R/sys || mount --rbind /sys $R/sys
trap 'umount -R $R/sys $R/proc $R/dev 2>/dev/null || true' EXIT

# What the skipped hooks would have done.
for m in $R/usr/lib/modules/*/; do
  rel=${m%/}; rel=${rel##*/}
  [[ -e $R/boot/vmlinuz-$rel ]] && chroot $R /usr/sbin/depmod "$rel"
done
chroot $R ldconfig
[[ -d $R/usr/share/glib-2.0/schemas ]] && chroot $R glib-compile-schemas /usr/share/glib-2.0/schemas
chroot $R update-desktop-database -q /usr/share/applications 2>/dev/null || true
chroot $R gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true
# libvirt's modular daemons, socket-activated as on an installed system
# (the default NAT network autostarts from the package's own link).
chroot $R systemctl enable virtqemud.socket virtnetworkd.socket virtstoraged.socket \
  virtnodedevd.socket virtsecretd.socket virtlogd.socket virtlockd.socket

echo "== checks"
ls $R/boot/vmlinuz-* | sed 's#^/b#  #'
chroot $R podman --version
chroot $R qemu-system-x86_64 --version | head -1
chroot $R virsh --version
chroot $R gh --version | head -1
chroot $R aws --version
chroot $R nft --version
names=$(printf '%s\n' "${pkgs[@]##*/}" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\..*$//')
bad=$(chroot $R pacman -Qk $names 2>/dev/null | grep -v " 0 missing files" || true)
[[ -z $bad ]] || { echo "files missing:"; echo "$bad"; exit 1; }
dep=$(chroot $R pacman -Dk 2>&1 | grep -v "database file for" | grep -v "^No database errors" || true)
[[ -z $dep ]] || { echo "dependency errors:"; echo "$dep"; exit 1; }
echo "every file present, every dependency known"
