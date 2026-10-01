#!/bin/bash
# Build the planned desktop layer (plan-blfs.sh first) inside the LFS
# chroot. Resumable: finished packages are skipped. STAGE=2 builds stage 2.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
exec podman run --rm --privileged --security-opt label=disable \
  -e STAGE="${STAGE:-1}" \
  -v ultimate-lfs-build:/mnt/build_dir -v ultimate-blfs-plan:/plan:ro \
  -v "$here:/work:ro" -v ultimate-pacman-cache:/var/cache/pacman/pkg \
  docker.io/library/archlinux:latest bash /work/blfs/driver.sh
