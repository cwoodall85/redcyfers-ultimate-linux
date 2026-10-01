#!/bin/bash
# The part of sign.sh that runs in the container (build tree at /b, key at /key).
set -euo pipefail
pacman -Sy --noconfirm --needed sbsigntools >/dev/null 2>&1
S=/b/usr/lib/ultimate/secureboot
mkdir -p $S

# Fedora's shim 16.1-5, as Fedora ships it. The EFI binaries are Microsoft-
# signed; the RPM's sha256 is pinned here (its files matched those Fedora
# installed on Chris's desktop, checked 2026-09-29).
SHIM_URL=https://kojipkgs.fedoraproject.org/packages/shim/16.1/5/x86_64/shim-x64-16.1-5.x86_64.rpm
SHIM_SHA=cb0289fb3d8356fe30dbf2a5a8c0cd9ba618df5ff54cf49887f75f2feb3f61c7
rpm=/b/sources/shim-x64-16.1-5.x86_64.rpm
[[ -f $rpm ]] || curl -sfL -o $rpm "$SHIM_URL"
echo "$SHIM_SHA  $rpm" | sha256sum -c - >/dev/null
w=$(mktemp -d); bsdtar -xf $rpm -C $w
install -m644 $w/usr/lib/efi/shim/16.1-5/EFI/fedora/shimx64.efi $S/shimx64.efi
install -m644 $w/usr/lib/efi/shim/16.1-5/EFI/fedora/mmx64.efi $S/mmx64.efi
install -m644 /key/MOK.cer $S/ultimate-mok.cer

# GRUB: the built-in config finds grub.cfg next to the GRUB that started.
cat > /b/tmp/sb-early.cfg <<'CFG'
set prefix=${cmdpath}
configfile ${cmdpath}/grub.cfg
CFG
# SBAT: shim's revocation list (Fedora 44, 2026-09) requires grub >= 4.
cat > /b/tmp/sb-sbat.csv <<'CSV'
sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
grub,4,Free Software Foundation,grub,2.14,https://www.gnu.org/software/grub/
grub.ultimate,1,Ultimate Linux,grub,2.14,https://github.com/cwoodall85/redcyfers-ultimate-linux
CSV
MODS="part_gpt part_msdos fat ext2 btrfs search search_fs_uuid search_fs_file search_label
      normal configfile linux chain boot echo test true minicmd sleep reboot halt ls cat
      all_video efi_gop gfxterm gfxmenu font gzio regexp probe loadenv efifwsetup"
chroot /b grub-mkimage -O x86_64-efi -d /usr/lib/grub/x86_64-efi -c /tmp/sb-early.cfg \
  -p "" --sbat /tmp/sb-sbat.csv -o /tmp/grubx64.efi $MODS
rm -f /b/tmp/sb-early.cfg /b/tmp/sb-sbat.csv
sbsign --key /key/MOK.key --cert /key/MOK.crt --output $S/grubx64.efi /b/tmp/grubx64.efi 2>/dev/null
rm -f /b/tmp/grubx64.efi

# The kernel(s): sign unless already signed with this key.
for k in /b/boot/vmlinuz-*; do
  if ! sbverify --cert /key/MOK.crt "$k" >/dev/null 2>&1; then
    sbsign --key /key/MOK.key --cert /key/MOK.crt --output "$k.signed" "$k" 2>/dev/null
    mv "$k.signed" "$k"
  fi
done

for f in $S/grubx64.efi /b/boot/vmlinuz-*; do
  sbverify --cert /key/MOK.crt "$f" >/dev/null && echo "signed: ${f#/b}"
done
objdump -s -j .sbat $S/grubx64.efi 2>/dev/null | grep -q grub.ultimate && echo "grubx64.efi carries SBAT data"
ls -la $S
