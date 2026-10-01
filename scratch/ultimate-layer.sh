#!/bin/bash
# Install the Ultimate layer (theme, Claude bar and tools, Claude Code, Mail,
# SSH, fonts) into the from-source system, tracked by its pacman. Build the
# packages first with ../build.sh packages.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
exec podman run --rm --privileged --security-opt label=disable \
  -v ultimate-lfs-build:/b -v "$here/../out/repo:/repo:ro" -v "$here:/work:ro" \
  -v ultimate-pacman-cache:/var/cache/pacman/pkg \
  docker.io/library/archlinux:latest bash /work/tools/container-ultimate-layer.sh
