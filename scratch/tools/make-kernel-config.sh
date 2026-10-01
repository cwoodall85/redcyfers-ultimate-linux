#!/bin/bash
# Regenerate kernel/config-<version> from x86_64_defconfig plus
# kernel/ultimate.fragment, in a throwaway Arch container.
#   tools/make-kernel-config.sh 7.1.8
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
ver=${1:?kernel version, e.g. 7.1.8}
podman run --rm --security-opt label=disable -v "$here/kernel:/k" \
  -v ultimate-pacman-cache:/var/cache/pacman/pkg docker.io/library/archlinux:latest bash -c "
  set -e
  pacman -Sy --noconfirm --needed base-devel bc flex bison openssl libelf pahole cpio >/dev/null 2>&1
  cd /tmp && curl -sL https://cdn.kernel.org/pub/linux/kernel/v${ver%%.*}.x/linux-$ver.tar.xz | tar xJ
  cd linux-$ver
  make -s x86_64_defconfig
  scripts/kconfig/merge_config.sh -m .config /k/ultimate.fragment >/dev/null
  make -s olddefconfig
  # Whole option families (kernel/all-of.list), see kernel/enable-families.sh
  bash /k/enable-families.sh /k/all-of.list
  # Report fragment lines the kernel silently dropped (bad names, unmet deps).
  grep -v '^#' /k/ultimate.fragment | grep = | while IFS== read -r k v; do
    got=\$(grep -E \"^\$k=|^# \$k is not set\" .config || echo \"\$k (absent)\")
    [[ \$got == \"\$k=\$v\" ]] || echo \"dropped: \$k=\$v -> \$got\"
  done
  cp .config /k/config-$ver
"
echo "wrote kernel/config-$ver"
