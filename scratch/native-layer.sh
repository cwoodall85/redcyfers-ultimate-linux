#!/bin/bash
# Install the packages built natively on Ultimate Linux (tools/native-makepkg.sh
# and hand makepkg -d runs) into the from-source system: the kernel, Podman,
# QEMU/libvirt, gh, aws and the small tools listed in native-packages.txt.
# Run after ultimate-layer.sh. Packages are looked up, newest first, in
# out/native/pkgs and then NATIVE_PKGS (default /mnt/storage/ultimate-pkgs).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
extra=${NATIVE_PKGS:-/mnt/storage/ultimate-pkgs}
exec podman run --rm --privileged --security-opt label=disable \
  -v ultimate-lfs-build:/b -v "$here/../out/native/pkgs:/native:ro" -v "$extra:/extra:ro" \
  -v "$here:/work:ro" docker.io/library/archlinux:latest bash /work/tools/container-native-layer.sh
