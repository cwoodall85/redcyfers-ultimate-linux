#!/bin/bash
# Boot the from-source image in a libvirt VM ("ultimate-src"). The VM
# writes to the image directly; rerun make-image.sh for a fresh one.
#
#   scratch/test-vm.sh                   (re)create the VM, BIOS firmware
#   scratch/test-vm.sh --uefi            UEFI firmware (Secure Boot off)
#   scratch/test-vm.sh --secureboot      UEFI with Secure Boot ON: Microsoft's
#                                        keys plus ours (secureboot/make-test-vars.sh)
#   scratch/test-vm.sh --target-disk     also attach a blank 40 GB disk
#                                        to install to (out/ultimate-target.qcow2)
#   scratch/test-vm.sh --existing-target attach the target disk as it is (TGT),
#                                        e.g. a disk with another system on it
#   scratch/test-vm.sh --installed       boot only the target disk, as an
#                                        installed machine would (with --uefi
#                                        or not)
#   scratch/test-vm.sh --destroy         remove the VM (keeps the images)
#
# Test logins: root / ultimate, and (once the desktop is built) the
# desktop user ultimate / ultimate.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# VM_NAME, IMG and TGT override the VM's name, the image and the target disk
# (scratch/test-image.sh uses its own, so a test never touches ultimate-src).
name=${VM_NAME:-ultimate-src}
export LIBVIRT_DEFAULT_URI=qemu:///system
img=${IMG:-$here/out/ultimate-src.qcow2}

destroy() {
  virsh destroy "$name" >/dev/null 2>&1 || true
  # --nvram only; never --remove-all-storage, which would delete the image.
  virsh undefine --nvram "$name" >/dev/null 2>&1 || virsh undefine "$name" >/dev/null 2>&1 || true
}
# libvirt's QEMU runs as "qemu" on Fedora and Arch, "libvirt-qemu" on
# Debian and Ubuntu; it needs to reach the images. As root with images
# outside a home directory, nothing needs granting.
quser=$(id -un qemu 2>/dev/null || id -un libvirt-qemu 2>/dev/null || true)
uefi=0 target=0 installed=0 secureboot=0
for a in "$@"; do
  case $a in
    --destroy) destroy; echo "removed $name"; exit 0 ;;
    --uefi) uefi=1 ;;
    --secureboot) uefi=1 secureboot=1 ;;
    --target-disk) target=1 ;;
    --existing-target) target=2 ;;
    --installed) installed=1 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
tgt=${TGT:-$here/out/ultimate-target.qcow2}
[[ -f $img ]] || { echo "no image; run scratch/make-image.sh" >&2; exit 1; }
if [[ $target == 1 ]]; then
  rm -f "$tgt"; qemu-img create -q -f qcow2 "$tgt" 40G
fi
[[ $target == 2 && ! -f $tgt ]] && { echo "no target disk at $tgt" >&2; exit 1; }
disks=()
[[ $installed == 1 ]] || disks+=(--disk "$img",format=qcow2,bus=virtio)
if [[ $target != 0 || $installed == 1 ]]; then
  [[ -f $tgt ]] || { echo "no target disk; use --target-disk first" >&2; exit 1; }
  [[ -n $quser && $(id -u) != 0 ]] && setfacl -m "u:$quser:rw" "$tgt"
  disks+=(--disk "$tgt",format=qcow2,bus=virtio)
fi
boot=()
[[ $uefi == 1 ]] && boot=(--boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no)
if [[ $secureboot == 1 ]]; then
  vars=${SB_VARS:-$here/out/ovmf-vars-ultimate.qcow2}
  [[ -f $vars ]] || { echo "no $vars; run scratch/secureboot/make-test-vars.sh" >&2; exit 1; }
  [[ -n $quser && $(id -u) != 0 ]] && setfacl -m "u:$quser:r" "$vars" 2>/dev/null || true
  code=${SB_CODE:-$here/out/ovmf-code-secboot.qcow2}
  [[ -f $code ]] || code=/usr/share/edk2/ovmf/OVMF_CODE_4M.secboot.qcow2
  boot=(--boot "loader=$code,loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template=$vars"
        --xml ./os/loader/@format=qcow2 --xml ./os/nvram/@format=qcow2
        --xml ./os/nvram/@templateFormat=qcow2 --features smm.state=on)
fi

if [[ -n $quser && $(id -u) != 0 ]]; then
  p=$(dirname "$img")
  while [[ $p != "$HOME" && $p != / ]]; do setfacl -m "u:$quser:x" "$p" 2>/dev/null || true; p=$(dirname "$p"); done
  setfacl -m "u:$quser:rw" "$img"
fi

destroy
# The newest OS id this host's osinfo database knows (older hosts lack 2024).
os=generic
for o in linux2024 linux2022 linux2020; do
  osinfo-query os short-id=$o 2>/dev/null | grep -q "$o" && { os=$o; break; }
done
virt-install --name "$name" --osinfo "$os" \
  --memory 8192 --vcpus 4 --cpu host-passthrough \
  "${disks[@]}" "${boot[@]}" \
  --network network=default,model=virtio \
  --graphics spice,listen=none --video virtio \
  --serial pty \
  --import --noautoconsole >/dev/null
echo "$name booting ($([[ $secureboot == 1 ]] && echo "UEFI, Secure Boot on" || { [[ $uefi == 1 ]] && echo UEFI || echo BIOS; })): ${disks[*]}"
echo "  console: virt-viewer -c qemu:///system $name     (login root / ultimate)"
if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v virt-viewer >/dev/null && [[ -z ${NO_VIEWER:-} ]]; then
  setsid virt-viewer -c qemu:///system --wait "$name" >/dev/null 2>&1 &
fi
