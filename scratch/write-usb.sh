#!/bin/bash
# Write the install image to a USB stick.
#
#   scratch/make-image.sh --usb            (an image sized for a stick, no test access)
#   scratch/write-usb.sh /dev/sdX          (asks for your password: writing a disk needs root)
#
# Refuses anything that isn't a removable USB disk, anything mounted, and
# sticks too small for the image. EVERYTHING on the stick is erased.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
img=${IMG:-$here/out/ultimate-src.qcow2}
dev=${1:?which device, e.g. /dev/sda (see lsblk)}
[[ -b $dev && $(lsblk -dno TYPE "$dev") == disk ]] || { echo "$dev is not a disk" >&2; exit 1; }
[[ $(lsblk -dno TRAN "$dev") == usb && $(lsblk -dno RM "$dev" | tr -d ' ') == 1 ]] ||
  { echo "$dev is not a removable USB disk; refusing" >&2; exit 1; }
if lsblk -no MOUNTPOINTS "$dev" | grep -q .; then
  echo "$dev has mounted partitions; unmount them first:" >&2
  lsblk -no NAME,MOUNTPOINTS "$dev" | grep "/" >&2; exit 1
fi
need=$(qemu-img info --output=json "$img" | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
have=$(lsblk -bdno SIZE "$dev")
(( have >= need )) || { echo "the image needs $((need / 2**20)) MiB; $dev has $((have / 2**20)) MiB (make-image.sh --usb makes it smaller)" >&2; exit 1; }
echo "Write $(basename "$img") ($((need / 2**20)) MiB) to $dev: $(lsblk -dno SIZE,VENDOR,MODEL "$dev" | xargs)"
read -rp "Everything on $dev will be erased. Type the device name to go ahead: " ok
[[ $ok == "$dev" ]] || { echo "cancelled"; exit 1; }
sudo qemu-img convert -p -O raw "$img" "$dev"
sync
echo "Done. Boot it with the firmware's boot menu (F11 on MSI boards), UEFI."
