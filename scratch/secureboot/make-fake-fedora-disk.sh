#!/bin/bash
# A disk that looks like a Fedora machine's, for dual-boot tests: GPT with an
# EFI system partition holding Fedora's real boot files -- shim (Microsoft-
# signed) under EFI/fedora and EFI/BOOT, and Fedora's GRUB (Fedora-signed;
# its grub.cfg here just prints a line) -- a "Fedora" btrfs partition laid
# out as Fedora does it (subvolumes root and home) with enough in it to test
# ultimate-migrate (a home with SSH files and a git config, a Wi-Fi profile,
# hid_apple's option, an fstab line for a data disk with an SELinux option),
# and free space for Ultimate Linux.
#   make-fake-fedora-disk.sh <out.qcow2> [size-GiB] [fedora-GiB]
set -euo pipefail
out=${1:?output qcow2}; size=${2:-60}; fed=${3:-10}
w=$(mktemp -d -p "$(dirname "$out")"); trap 'rm -rf "$w"' EXIT
podman run --rm --security-opt label=disable -v "$w:/w" -v ultimate-lfs-build:/b:ro \
  docker.io/library/archlinux:latest bash -c "
  set -e
  pacman -Sy --noconfirm --needed dosfstools mtools e2fsprogs btrfs-progs util-linux qemu-img >/dev/null 2>&1
  cd /w
  truncate -s ${size}G disk.raw
  sfdisk -q disk.raw <<PT
label: gpt
size=600MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=\"EFI System Partition\"
size=${fed}GiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"fedora\"
PT
  truncate -s 600M esp.fat; mkfs.fat -F 32 -n ESP esp.fat >/dev/null
  mmd -i esp.fat ::/EFI ::/EFI/fedora ::/EFI/BOOT
  S=/b/usr/lib/ultimate/secureboot
  mcopy -i esp.fat \$S/shimx64.efi \$S/mmx64.efi ::/EFI/fedora/
  mcopy -i esp.fat \$S/shimx64.efi ::/EFI/BOOT/BOOTX64.EFI
  # Fedora 44's GRUB, pinned (matched the one installed on Chris's desktop)
  curl -sfL -o grub.rpm https://kojipkgs.fedoraproject.org/packages/grub2/2.12/64.fc44/x86_64/grub2-efi-x64-2.12-64.fc44.x86_64.rpm
  echo '67a72f34916a0c59aee824459a3d10f76ed62e6524c8f8136692e8370720fa66  grub.rpm' | sha256sum -c - >/dev/null
  mkdir g && bsdtar -xf grub.rpm -C g
  mcopy -i esp.fat g/usr/lib/efi/grub2/*/EFI/fedora/grubx64.efi ::/EFI/fedora/grubx64.efi
  printf 'echo FEDORA-GRUB-STARTED\nsleep 600\n' > fedora-grub.cfg; mcopy -i esp.fat fedora-grub.cfg ::/EFI/fedora/grub.cfg
  R=froot/root H=froot/home/chris
  mkdir -p \$R/etc/NetworkManager/system-connections \$R/etc/modprobe.d \$H/.ssh \$H/.config/ultimate-mail
  echo 'fedora data that must survive' > \$H/MARKER
  echo 'fake-key-for-tests' > \$H/.ssh/id_test; echo 'Host web01' > \$H/.ssh/config
  printf '[user]\\n\\tname = CI\\n' > \$H/.gitconfig
  echo '{}' > \$H/.config/ultimate-mail/settings.json
  printf '[connection]\\nid=TestWiFi\\ntype=wifi\\n' > \$R/etc/NetworkManager/system-connections/TestWiFi.nmconnection
  echo 'options hid_apple fnmode=2' > \$R/etc/modprobe.d/hid_apple.conf
  printf 'UUID=11111111-2222-3333-4444-555555555555 / btrfs subvol=root 0 0\\nUUID=aaaa0000-bbbb-cccc-dddd-eeeeffff0000 /mnt/storage ext4 defaults,nofail,x-systemd.device-timeout=10,context=system_u:object_r:samba_share_t:s0 0 2\\n' > \$R/etc/fstab
  chown -R 1000:1000 \$H
  truncate -s ${fed}G fed.btrfs
  mkfs.btrfs -q -f -L fedora --rootdir froot --subvol root --subvol home fed.btrfs
  dd if=esp.fat of=disk.raw bs=1M seek=1 conv=notrunc,sparse status=none
  dd if=fed.btrfs of=disk.raw bs=1M seek=601 conv=notrunc,sparse status=none
  sfdisk -l disk.raw | tail -3
  qemu-img convert -O qcow2 disk.raw disk.qcow2
  rm -rf froot"
mv "$w/disk.qcow2" "$out"
echo "wrote $out"
