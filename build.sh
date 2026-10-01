#!/bin/bash
# Build Ultimate Linux: the packages into out/repo, then the ISO into out/iso.
#
#   ./build.sh            packages and ISO
#   ./build.sh packages   only the package repository
#   ./build.sh iso        only the ISO, from the packages already built
#
# Everything runs in a throwaway Arch Linux container, so this works on any
# host with Podman -- including this Fedora machine. mkarchiso needs loop
# devices and mounts, hence --privileged.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$here/out/repo" "$here/out/iso"

# Snapshot the apps that live in their own repositories: committed work
# only (git archive HEAD), versioned r<commits>.<hash> like an Arch VCS
# package. Override a location with e.g. ULTIMATE_MAIL_SRC=/path.
mkdir -p "$here/out/sources"
snapshot() {
  local name=$1 src=$2
  [[ -d $src/.git ]] || { echo "no git repository at $src (set the *_SRC variable)" >&2; exit 1; }
  git -C "$src" archive --prefix="$name/" -o "$here/out/sources/$name.tar.gz" HEAD
  printf 'r%s.%s\n' "$(git -C "$src" rev-list --count HEAD)" \
    "$(git -C "$src" rev-parse --short HEAD)" > "$here/out/sources/$name.VERSION"
  if [[ -n $(git -C "$src" status --porcelain --untracked-files=no) ]]; then
    echo "note: $name has uncommitted changes; the package uses HEAD" >&2
  fi
}
snapshot ultimate-mail "${ULTIMATE_MAIL_SRC:-$HOME/projects/ultimate-mail}"
snapshot ultimate-ssh "${ULTIMATE_SSH_SRC:-$HOME/projects/ultimate-ssh}"

podman volume exists ultimate-pacman-cache || podman volume create ultimate-pacman-cache >/dev/null

# label=disable rather than :z mounts: :z relabels every file under the
# project, which fails on an ISO that libvirt currently owns and would
# fight libvirt's own labels on it.
exec podman run --rm --privileged --security-opt label=disable \
  -v "$here:/src" \
  -v "$here/out/repo:/ultimate-repo" \
  -v ultimate-pacman-cache:/var/cache/pacman/pkg \
  docker.io/library/archlinux:latest \
  bash /src/tools/container-build.sh "${1:-all}"
