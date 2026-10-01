#!/bin/bash
# sign-kernel.sh FILE -- sign a kernel image in place with the Ultimate Linux
# MOK key, using sbsign from a throwaway Arch container (the from-source
# base has no sbsigntools). Verifies the signature afterwards.
set -euo pipefail
f=$(readlink -f "${1:?kernel image}")
K=${SB_KEY_DIR:-$HOME/.local/share/ultimate-linux/secureboot}
for x in MOK.key MOK.crt; do [[ -f $K/$x ]] || { echo "sign-kernel: no $K/$x" >&2; exit 1; }; done
podman run --rm --security-opt label=disable --network=host \
  -v "$K:/key:ro" -v "$(dirname "$f"):/w" docker.io/library/archlinux:latest bash -c "
  set -e
  pacman -Sy --noconfirm --needed sbsigntools >/dev/null 2>&1
  n=/w/$(basename "$f")
  if sbverify --cert /key/MOK.crt \$n >/dev/null 2>&1; then echo 'already signed'; exit 0; fi
  sbsign --key /key/MOK.key --cert /key/MOK.crt --output \$n.signed \$n 2>/dev/null
  mv \$n.signed \$n
  sbverify --cert /key/MOK.crt \$n
"
