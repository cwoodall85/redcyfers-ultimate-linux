#!/bin/bash
# Make a bootable disk image from the finished from-source build:
# scratch/out/ultimate-src.qcow2, bootable under BIOS and UEFI, carrying
# the installer (ultimate-install). TEST_SSH_KEY=<public key> lets root in
# by that key, for automated tests; never set it for an image you hand out.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# --usb: sized to fit a 16 GB stick (little free space in the live session),
# and never with test access.
# --usb images are release images (RELEASE=1): no known passwords, a live
# session that logs itself in. RELEASE=1 alone (with TEST_SSH_KEY) builds
# the same thing for the test VMs.
if [[ ${1:-} == --usb ]]; then
  export IMAGE_SLACK_PCT=7 IMAGE_EXTRA_MB=768 RELEASE=1
  [[ -z ${TEST_SSH_KEY:-} ]] || { echo "--usb images never carry TEST_SSH_KEY" >&2; exit 1; }
fi
# The image is brought up to date from our repositories when they are here
# (scratch/repo/make-repo.sh); REPO= (empty) builds from the tree as it is.
REPO=${REPO-/mnt/storage/ultimate-repo}
repo_mount=(); [[ -n $REPO && -d $REPO/ultimate ]] && repo_mount=(-v "$REPO:/repo:ro")
mkdir -p "$here/out"
podman run --rm --privileged --security-opt label=disable \
  -v ultimate-lfs-build:/b:ro -v "$here/out:/out" -v "$here:/work:ro" "${repo_mount[@]}" \
  -v ultimate-pacman-cache:/var/cache/pacman/pkg -e TEST_SSH_KEY -e IMAGE_SLACK_PCT -e IMAGE_EXTRA_MB -e RELEASE \
  docker.io/library/archlinux:latest bash /work/tools/container-image.sh
# A VM using the old image leaves it owned by qemu; replace, not overwrite.
rm -f "$here/out/ultimate-src.qcow2"
qemu-img convert -O qcow2 "$here/out/ultimate-src.raw" "$here/out/ultimate-src.qcow2"
rm -f "$here/out/ultimate-src.raw"
ls -lh "$here/out/ultimate-src.qcow2"
