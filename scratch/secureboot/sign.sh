#!/bin/bash
# Secure Boot: sign what boots, in the build tree, so the packages and the
# image carry signed files and no machine ever holds the signing key.
#
#   scratch/secureboot/sign.sh            (key in ~/.local/share/ultimate-linux/secureboot)
#   SB_KEY_DIR=/path scratch/secureboot/sign.sh
#
# The chain: firmware -> shim (Fedora's build, signed by Microsoft; trusts
# keys the owner enrolls: "MOK") -> our GRUB, signed with our key -> the
# kernel, signed with our key (GRUB asks shim to check it).
#
# Into /usr/lib/ultimate/secureboot/ in the build tree:
#   shimx64.efi, mmx64.efi   Fedora's shim and MokManager (pinned, checked)
#   grubx64.efi              our GRUB 2.14, every module built in (Secure
#                            Boot's lockdown forbids loading any from disk),
#                            SBAT data (shim refuses GRUB without it), and a
#                            built-in config that reads grub.cfg from the
#                            directory it was started from -- so one signed
#                            GRUB serves the USB image and every install
#   ultimate-mok.cer         the public certificate to enroll (mokutil
#                            --import, or MokManager's "Enroll key from disk")
# and the kernel(s) in /boot are signed in place.
#
# Key directory: MOK.key, MOK.crt (PEM), MOK.cer (DER). Never commit it.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
K=${SB_KEY_DIR:-$HOME/.local/share/ultimate-linux/secureboot}
for f in MOK.key MOK.crt MOK.cer; do [[ -f $K/$f ]] || { echo "no $K/$f" >&2; exit 1; }; done
podman run --rm --security-opt label=disable -v ultimate-lfs-build:/b -v "$K:/key:ro" \
  -v "$here/secureboot:/sb:ro" -v ultimate-pacman-cache:/var/cache/pacman/pkg \
  docker.io/library/archlinux:latest bash /sb/sign-in-container.sh
