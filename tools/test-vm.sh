#!/bin/bash
# Boot the newest Ultimate Linux ISO in a libvirt VM on qemu:///system,
# the same connection as um-test, with a Spice console for virt-viewer.
#
#   tools/test-vm.sh             (re)create the VM from the newest ISO and boot it
#   tools/test-vm.sh --keep-disk re-point the VM at the newest ISO, keep the installed disk
#   tools/test-vm.sh --destroy   remove the VM and its disk
#
# The VM boots its disk first and falls through to the ISO while the disk is
# blank, so after an install it comes up in the installed system.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
name=ultimate-test
conn=qemu:///system
export LIBVIRT_DEFAULT_URI=$conn
disk_gb=40

destroy() {
  virsh destroy "$name" >/dev/null 2>&1 || true
  # Only the VM's own disk. --remove-all-storage would also delete the
  # attached ISO, because libvirt counts the cdrom as the VM's storage.
  virsh undefine "$name" --nvram --storage vda >/dev/null 2>&1 || true
}

if [[ ${1:-} == --destroy ]]; then destroy; echo "removed $name"; exit 0; fi

iso=$(ls -t "$here"/out/iso/*.iso 2>/dev/null | head -1 || true)
[[ -n $iso ]] || { echo "no ISO in out/iso; run ./build.sh first" >&2; exit 1; }

# libvirt's qemu runs as the qemu user: let it reach and read the ISO.
p=$here
while [[ $p != "$HOME" && $p != / ]]; do setfacl -m u:qemu:x "$p"; p=$(dirname "$p"); done
setfacl -m u:qemu:x "$here/out" "$here/out/iso"
setfacl -m u:qemu:r "$iso"

if [[ ${1:-} == --keep-disk ]] && virsh dominfo "$name" >/dev/null 2>&1; then
  virsh destroy "$name" >/dev/null 2>&1 || true
  virsh change-media "$name" sda "$iso" --config --force >/dev/null
  virsh start "$name" >/dev/null
else
  destroy
  virt-install --connect "$conn" \
    --name "$name" \
    --osinfo archlinux \
    --memory 8192 --vcpus 4 --cpu host-passthrough \
    --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,bootmenu.enable=no \
    --disk size=$disk_gb,format=qcow2,bus=virtio,boot.order=1 \
    --disk "$iso",device=cdrom,bus=sata,readonly=on,boot.order=2 \
    --network network=default,model=virtio \
    --graphics spice,listen=none \
    --video virtio \
    --channel spicevmc \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --serial pty \
    --import --noautoconsole >/dev/null
fi

echo "$name booting $(basename "$iso")"
echo "  console:      virt-viewer -c $conn $name"
echo "  serial log:   virsh -c $conn console $name"
if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v virt-viewer >/dev/null && [[ -z ${NO_VIEWER:-} ]]; then
  setsid virt-viewer -c "$conn" --wait "$name" >/dev/null 2>&1 &
fi
