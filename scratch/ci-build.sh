#!/bin/bash
# Build Ultimate Linux from source, unattended, on a fresh machine (the AWS
# build box) or here. One entry point: it gets the code, builds the stages
# asked for, packs what came out, and exits non-zero on the first failure.
#
#   scratch/ci-build.sh                    everything, in order
#   scratch/ci-build.sh blfs2 blfs3 image  just those steps
#
# Steps, in order (each resumes where an earlier run stopped, so a spot
# interruption costs only the package that was building):
#   base      LFS 13.1 base system (scratch/build.sh)
#   blfs1     plan + build the desktop (Plasma)          -- blfs/targets.conf
#   blfs2     plan + build stage 2 (apps' libraries, net tools)
#   blfs3     plan + build stage 3 (installer tools, GRUB for UEFI)
#   blfs4     plan + build stage 4 (firmware, CPU microcode, cryptsetup, the kernel)
#   sign      Secure Boot: sign the kernel and GRUB, add shim (secureboot/sign.sh);
#             needs SB_KEY_DIR (MOK.key/.crt/.cer); skipped, with a warning, without it
#   desktop   package the desktop layer: pacman packages + repository (pkg/)
#   packages  the Ultimate packages (../build.sh packages)
#   layer     install them into the system (ultimate-layer.sh)
#   image     the BIOS + UEFI disk image (make-image.sh)
#   test      boot, install and check it in KVM (test-image.sh); needs /dev/kvm
#   pack      copy outputs, logs and timings into the artifact directory
#
# Environment (all optional):
#   DATA=/data            where everything lives: podman storage (the build
#                         volumes), sources, books, outputs, artifacts. Put a
#                         persistent disk here so state survives the machine.
#                         Default: this checkout's scratch/out/ci.
#   REPO=...              where to clone ultimate-linux from, when this script
#                         is run from outside a checkout.
#                         Default: homebase-git:/srv/git/ultimate-linux.git
#   MAIL_REPO, SSH_REPO   the Ultimate Mail and Ultimate SSH repositories
#                         (defaults: homebase-git:/srv/git/ultimate-{mail,ssh}.git,
#                         or ~/projects/ultimate-{mail,ssh} when they exist)
#   BUILD_ID=...          names the artifact directory. Default: UTC time + commit.
#   TEST_SSH_KEY=...      passed to make-image.sh (root SSH by that key, for
#                         automated tests only; never for an image you hand out).
#                         When the steps include "test" and this isn't set, a
#                         throwaway key is made in $DATA/test-key.
#   SHUTDOWN_WHEN_DONE=1  power off at the end, pass or fail. For the build box,
#                         which terminates itself on shutdown. Never the default.
#
# Needs: podman, git, python3, qemu-img, and outbound internet (sources come
# from the LFS/BLFS mirrors and upstream sites). No prompts anywhere.
set -euo pipefail

steps_all=(base blfs1 blfs2 blfs3 blfs4 sign desktop packages layer image test pack)

# --- run from a checkout; clone one first if this copy is standalone ---------
self=$(readlink -f "$0")
here=$(cd "$(dirname "$self")" && pwd)
if [[ ! -f $here/build.sh || ! -d $here/../.git ]]; then
  REPO=${REPO:-homebase-git:/srv/git/ultimate-linux.git}
  DATA=${DATA:?set DATA when running outside a checkout}
  mkdir -p "$DATA/src"
  if [[ -d $DATA/src/ultimate-linux/.git ]]; then
    git -C "$DATA/src/ultimate-linux" pull -q --ff-only
  else
    git clone -q "$REPO" "$DATA/src/ultimate-linux"
  fi
  exec "$DATA/src/ultimate-linux/scratch/ci-build.sh" "$@"
fi
top=$(cd "$here/.." && pwd)

if [[ ${SHUTDOWN_WHEN_DONE:-} == 1 ]]; then
  trap 'rc=$?; echo "ci-build: exit $rc; shutting down"; sync; shutdown -h now' EXIT
fi

steps=("$@"); ((${#steps[@]})) || steps=("${steps_all[@]}")
for s in "${steps[@]}"; do
  [[ " ${steps_all[*]} " == *" $s "* ]] || { echo "unknown step: $s (steps: ${steps_all[*]})" >&2; exit 2; }
done

# --- where state lives ----------------------------------------------------------
DATA=${DATA:-$here/out/ci}
mkdir -p "$DATA"/{containers,src,books,artifacts}
DATA=$(cd "$DATA" && pwd)
# Podman keeps the build volumes (~25 GB) under its storage root; point it at
# DATA so a persistent disk holds them. Only when DATA is not the default:
# on the desktop the existing volumes stay where they are.
if [[ -n ${DATA_IS_STORAGE:-} || $DATA != "$here/out/ci" ]]; then
  conf=$DATA/storage.conf
  cat > "$conf" <<EOF
[storage]
driver = "overlay"
graphroot = "$DATA/containers/storage"
runroot = "$DATA/containers/run"
EOF
  export CONTAINERS_STORAGE_CONF=$conf
fi
export JHALFS_SRC=${JHALFS_SRC:-$DATA/src/jhalfs}
export BOOKS=${BOOKS:-$DATA/books}

# The Ultimate apps' repositories, for the packages step.
clone_or_pull() {  # name url
  local d=$DATA/src/$1
  if [[ -d $d/.git ]]; then git -C "$d" pull -q --ff-only; else git clone -q "$2" "$d"; fi
  echo "$d"
}

commit=$(git -C "$top" rev-parse --short HEAD)
BUILD_ID=${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$commit}
ART=$DATA/artifacts/$BUILD_ID
mkdir -p "$ART"
exec > >(tee -a "$ART/ci.log") 2>&1
echo "ci-build $BUILD_ID: steps ${steps[*]}; DATA=$DATA; $(nproc) cores, $(free -g | awk '/Mem:/{print $2}') GB"
for t in podman git python3 qemu-img; do command -v $t >/dev/null || { echo "missing $t" >&2; exit 1; }; done

step_times=$ART/steps.tsv
[[ -f $step_times ]] || printf 'step\tstart\tend\tseconds\tresult\n' > "$step_times"
run_step() {  # name command...
  local name=$1; shift
  local t0=$(date +%s)
  echo "== step $name  $(date -u +%H:%M:%S)"
  if "$@"; then
    printf '%s\t%s\t%s\t%s\tok\n' "$name" "$t0" "$(date +%s)" $(( $(date +%s) - t0 )) >> "$step_times"
  else
    local rc=$?
    printf '%s\t%s\t%s\t%s\tfailed\n' "$name" "$t0" "$(date +%s)" $(( $(date +%s) - t0 )) >> "$step_times"
    echo "!! step $name failed (exit $rc)"
    return $rc
  fi
}

do_packages() {
  local mail ssh
  if [[ -z ${MAIL_REPO:-} && -d $HOME/projects/ultimate-mail/.git ]]; then
    mail=$HOME/projects/ultimate-mail
  else
    mail=$(clone_or_pull ultimate-mail "${MAIL_REPO:-homebase-git:/srv/git/ultimate-mail.git}")
  fi
  if [[ -z ${SSH_REPO:-} && -d $HOME/projects/ultimate-ssh/.git ]]; then
    ssh=$HOME/projects/ultimate-ssh
  else
    ssh=$(clone_or_pull ultimate-ssh "${SSH_REPO:-homebase-git:/srv/git/ultimate-ssh.git}")
  fi
  ULTIMATE_MAIL_SRC=$mail ULTIMATE_SSH_SRC=$ssh "$top/build.sh" packages
}

do_pack() {
  echo "== packing into $ART"
  # the image, compressed (12 GB raw qcow2 -> a few GB)
  if [[ -f $here/out/ultimate-src.qcow2 ]]; then
    qemu-img convert -c -O qcow2 "$here/out/ultimate-src.qcow2" "$ART/ultimate-src.qcow2"
  fi
  # the Ultimate packages and the base system's pacman packages
  mkdir -p "$ART/repo" "$ART/base-packages" "$ART/desktop-packages" "$ART/logs"
  cp -a "$top/out/repo/." "$ART/repo/" 2>/dev/null || true
  cp -a "$here/out/desktop-pkgs/." "$ART/desktop-packages/" 2>/dev/null || true
  podman run --rm -v ultimate-lfs-build:/b:ro -v "$ART:/art" docker.io/library/archlinux:latest bash -c '
    cp -a /b/var/lib/packages/. /art/base-packages/ 2>/dev/null || true
    mkdir -p /art/logs/jhalfs /art/logs/blfs
    cp -a /b/jhalfs/logs/. /art/logs/jhalfs/ 2>/dev/null || true
    cp -a /b/blfs/logs/. /art/logs/blfs/ 2>/dev/null || true
    cp -a /b/blfs/timings.tsv /art/logs/blfs-timings.tsv 2>/dev/null || true
    chown -R 0:0 /art'   # container root is whoever runs podman: root, or the rootless user
  cp -a "$here"/out/*.log "$ART/logs/" 2>/dev/null || true
  "$here/tools/build-timings.sh" "$BUILD_ID" >/dev/null && cp "$here/out/timings/$BUILD_ID.tsv" "$ART/timings.tsv"
  # what's here, with sizes and checksums
  {
    echo "build: $BUILD_ID"
    echo "commit: $(git -C "$top" rev-parse HEAD)"
    echo "host: $(nproc) cores, $(free -g | awk '/Mem:/{print $2}') GB RAM"
    echo "steps: ${steps[*]}"
    echo
    (cd "$ART" && du -sh ultimate-src.qcow2 repo base-packages desktop-packages logs 2>/dev/null)
    echo
    (cd "$ART" && find . -maxdepth 2 -type f \( -name '*.qcow2' -o -name '*.pkg.tar.*' \) -print0 \
      | sort -z | xargs -0 -r sha256sum)
  } > "$ART/MANIFEST"
  cat "$ART/MANIFEST" | head -12
}

# The test step logs in with a throwaway key the image was made with.
if [[ " ${steps[*]} " == *" test "* && -z ${TEST_SSH_KEY:-} ]]; then
  [[ -f $DATA/test-key ]] || ssh-keygen -q -t ed25519 -N "" -C ultimate-ci -f "$DATA/test-key"
  export TEST_SSH_KEY=$(cat "$DATA/test-key.pub") TEST_KEY=$DATA/test-key
fi

for s in "${steps[@]}"; do
  case $s in
    base)     run_step base "$here/build.sh" ;;
    blfs1)    run_step plan1 env STAGE=1 "$here/plan-blfs.sh"
              run_step blfs1 env STAGE=1 "$here/blfs-build.sh" ;;
    blfs2)    run_step plan2 env STAGE=2 "$here/plan-blfs.sh"
              run_step blfs2 env STAGE=2 "$here/blfs-build.sh" ;;
    blfs3)    run_step plan3 env STAGE=3 "$here/plan-blfs.sh"
              run_step blfs3 env STAGE=3 "$here/blfs-build.sh" ;;
    blfs4)    run_step plan4 env STAGE=4 "$here/plan-blfs.sh"
              run_step blfs4 env STAGE=4 "$here/blfs-build.sh" ;;
    sign)     if [[ -n ${SB_KEY_DIR:-} || -f $HOME/.local/share/ultimate-linux/secureboot/MOK.key ]]; then
                run_step sign "$here/secureboot/sign.sh"
              else
                echo "!! step sign skipped: no signing key (SB_KEY_DIR); the image will need Secure Boot off"
              fi ;;
    desktop)  run_step desktop "$here/pkg/package-desktop.sh" ;;
    packages) run_step packages do_packages ;;
    layer)    run_step layer "$here/ultimate-layer.sh" ;;
    image)    run_step image "$here/make-image.sh" ;;
    test)     run_step test env OUT="$ART/test" "$here/test-image.sh" ;;
    pack)     run_step pack do_pack ;;
  esac
done
echo "ci-build $BUILD_ID: done; artifacts in $ART"
