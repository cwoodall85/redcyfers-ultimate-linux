#!/bin/bash
# Make a downloadable release from the release image (make-image.sh --usb):
#
#   scratch/make-image.sh --usb
#   scratch/release/make-release.sh VERSION
#
# Writes scratch/out/release/VERSION/:
#   ultimate-linux-VERSION.img.xz         the raw disk image, xz (balenaEtcher
#                                         and `xz -dc | dd` both take it)
#   ultimate-linux-VERSION.img.xz.sha256  sha256sum format, relative name
#   ultimate-linux-VERSION.img.xz.sig     detached signature, the repository
#                                         signing subkey (ultimate-keyring)
#   INSTALL.md                            docs/INSTALL.md
# Refuses an image that still has test access or known passwords. Nothing
# is uploaded: copy the directory to the release host yourself.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: make-release.sh VERSION (e.g. 2026.10.01)}
[[ $VERSION =~ ^[0-9A-Za-z._-]+$ ]] || { echo "bad version: $VERSION" >&2; exit 2; }
IMG=${IMG:-$here/out/ultimate-src.qcow2}
OUT=$here/out/release/$VERSION
SIGN_HOME=${SIGN_HOME:-$HOME/.local/share/ultimate-linux/repo-signing/signer}
name=ultimate-linux-$VERSION.img
[[ -f $IMG ]] || { echo "no image at $IMG (make-image.sh --usb)" >&2; exit 1; }
[[ ! -e $OUT ]] || { echo "$OUT exists" >&2; exit 1; }

# The image must be a release image: look inside before anything else.
podman run --rm --security-opt label=disable -v "$(dirname "$(readlink -f "$IMG")"):/i:ro" \
  docker.io/library/archlinux:latest bash -c '
  set -e
  pacman -Sy --noconfirm --needed qemu-img e2fsprogs >/dev/null 2>&1
  qemu-img convert -O raw /i/'"$(basename "$IMG")"' /tmp/d.raw
  start=$(sfdisk -d /tmp/d.raw 2>/dev/null | awk -F"[=,]" "/d.raw2/{gsub(/ /,\"\",\$2); print \$2}")
  dd if=/tmp/d.raw of=/tmp/root.ext4 bs=512 skip=$start status=none
  bad=0
  debugfs -R "cat /root/.ssh/authorized_keys" /tmp/root.ext4 2>/dev/null | grep -q . && { echo "test SSH key present"; bad=1; }
  debugfs -R "stat /etc/ssh/sshd_config.d/90-ultimate-test.conf" /tmp/root.ext4 2>&1 | grep -q "Inode:" && { echo "test sshd config present"; bad=1; }
  debugfs -R "cat /etc/shadow" /tmp/root.ext4 2>/dev/null | awk -F: "\$1==\"root\" && \$2 !~ /^[*!]/{print \"root has a password\"; exit 1}" || bad=1
  debugfs -R "stat /usr/bin/claude" /tmp/root.ext4 2>&1 | grep -q "Inode:" && { echo "Claude Code binary in the image (not redistributable)"; bad=1; }
  debugfs -R "stat /opt/google" /tmp/root.ext4 2>&1 | grep -q "Inode:" && { echo "Google Chrome in the image (not redistributable)"; bad=1; }
  debugfs -R "cat /etc/sddm.conf.d/50-ultimate-live.conf" /tmp/root.ext4 2>/dev/null | grep -q User=ultimate || { echo "not a release image (no live session)"; bad=1; }
  exit $bad' || { echo "REFUSING: $IMG is not a clean release image" >&2; exit 1; }

mkdir -p "$OUT"
qemu-img convert -O raw "$IMG" "$OUT/$name"
xz -T0 -6 "$OUT/$name"
( cd "$OUT" && sha256sum "$name.xz" > "$name.xz.sha256" )
GNUPGHOME=$SIGN_HOME gpg --batch --yes --detach-sign -o "$OUT/$name.xz.sig" "$OUT/$name.xz"
cp "$here/../docs/INSTALL.md" "$OUT/INSTALL.md"
ls -lh "$OUT"
