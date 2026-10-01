#!/bin/bash
# UEFI variables for Secure Boot tests: the VM firmware's Secure Boot
# variable store (Microsoft's keys enrolled, as on real machines) with the
# Ultimate Linux certificate added to "db". Shim trusts db as well as the
# keys an owner enrolls with MokManager, so this stands in for that one-time
# enrollment. Output: scratch/out/ovmf-vars-ultimate.qcow2 (test-vm.sh
# --secureboot uses it).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
K=${SB_KEY_DIR:-$HOME/.local/share/ultimate-linux/secureboot}
# Fedora's edk2-ovmf ships the Secure Boot firmware with Microsoft's keys
# already enrolled; Arch's (and so Ultimate's) doesn't. The firmware and
# its variable store must match, so both come from the Fedora container
# and land in out/ (test-vm.sh --secureboot uses out/ovmf-code-secboot.qcow2).
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cp "$K/MOK.crt" "$w/"
podman run --rm --security-opt label=disable -v "$w:/w" registry.fedoraproject.org/fedora:44 bash -c '
  set -e
  dnf -q -y install python3-virt-firmware qemu-img edk2-ovmf >/dev/null
  cd /w
  cp /usr/share/edk2/ovmf/OVMF_VARS_4M.secboot.qcow2 in.qcow2
  cp /usr/share/edk2/ovmf/OVMF_CODE_4M.secboot.qcow2 code.qcow2
  qemu-img convert -O raw in.qcow2 in.raw
  virt-fw-vars --input in.raw --output out.raw \
    --add-db 26dc4851-195f-4ae1-9a19-fbf883bbb35e MOK.crt >/dev/null
  virt-fw-vars --input out.raw --print 2>/dev/null | grep -i -E "Ultimate|Microsoft" | sed "s/^/  /" | head -8
  qemu-img convert -O qcow2 out.raw out.qcow2'
mkdir -p "$here/out"
cp "$w/out.qcow2" "$here/out/ovmf-vars-ultimate.qcow2"
cp "$w/code.qcow2" "$here/out/ovmf-code-secboot.qcow2"
echo "wrote out/ovmf-vars-ultimate.qcow2 and out/ovmf-code-secboot.qcow2"
