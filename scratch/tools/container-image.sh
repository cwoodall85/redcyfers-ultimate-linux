#!/bin/bash
# Runs INSIDE a container (see ../make-image.sh). Turns the finished build
# in /b into a disk image at /out/ultimate-src.raw that boots under BIOS
# and UEFI -- in a VM, or written to a USB stick as the installer -- without
# loop devices or mounts, which rootless Podman doesn't have:
#   * an MBR partition table (sfdisk) with a fixed disk id, so partition
#     UUIDs are known in advance: p1 the EFI system partition (FAT32),
#     p2 the root filesystem (ext4, label ultimate-root)
#   * both filesystems written from directories (mkfs.ext4 -d; mkfs.fat
#     plus mtools) and copied in with dd
#   * our own GRUB 2.14 for both firmwares: for BIOS, boot.img in the MBR
#     and core.img right after it; for UEFI, EFI/BOOT/BOOTX64.EFI on the
#     ESP (the fallback path, so no firmware boot entry is needed). Each
#     finds the root filesystem by its label and reads /boot/grub/grub.cfg.
#   * the kernel mounts root by PARTUUID (no initramfs, so no UUID=).
# Everything below edits a staging copy; the build tree is left as built.
set -euo pipefail
pacman -Sy --noconfirm --needed e2fsprogs util-linux rsync dosfstools mtools >/dev/null 2>&1

R=/stage
rm -rf $R && mkdir $R
echo "== staging the root filesystem"
rsync -aHAX --numeric-ids --filter='-x security.selinux' --exclude=/sources --exclude=/jhalfs --exclude=/tools --exclude=/blfs \
  --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' \
  --exclude='/tmp/*' --exclude=/var/lib/packages /b/ $R/

# Bring the copy up to date from our own repositories (make-image.sh mounts
# them at /repo when they exist): every package at the version the repos
# serve, plus what the build tree never had (UPDATE_EXTRA). The packages
# were built and signed on this machine; pacman checks the signatures once
# installed systems update from the hosted copy.
UPDATE_EXTRA="ultimate-keyring ultimate-mirrorlist ultimate-browser kdeconnect
  noto-fonts noto-fonts-emoji piper-tts whisper-cpp fastfetch"
# Installed by the build (stage 5) before they were packaged: their files
# are in the tree but pacman doesn't know them. Register them over those
# files (UPDATE_ADOPT), then update as usual.
UPDATE_ADOPT="python-pyparsing ostree flatpak"
# Never in a published image (not ours to redistribute): Claude Code comes
# from Anthropic's installer at first login instead.
# Also the build's own first kernel package ("kernel", BLFS), superseded by
# linux-ultimate: nearly all of its files are gone, and pacman -Qk says so.
UPDATE_REMOVE="claude-code google-chrome kernel"
if [[ -d /repo/ultimate/os/x86_64 ]]; then
  echo "== updating the copy from the repositories"
  cat > /tmp/update.conf <<'CONF'
[options]
Architecture = x86_64
SigLevel = Never
CacheDir = /tmp/update-cache
[ultimate]
Server = file:///repo/$repo/os/$arch
[ultimate-desktop]
Server = file:///repo/$repo/os/$arch
[ultimate-base]
Server = file:///repo/$repo/os/$arch
CONF
  mkdir -p /tmp/update-cache
  for f in dev sys proc; do mount --rbind /$f $R/$f; done
  pm() { pacman --config /tmp/update.conf --root $R --dbpath $R/var/lib/pacman "$@"; }
  pm -Sy >/dev/null
  adopt=(); for p in $UPDATE_ADOPT; do pm -Q "$p" >/dev/null 2>&1 || adopt+=("$p"); done
  ((${#adopt[@]} == 0)) || pm --noconfirm -S --needed --overwrite '*' "${adopt[@]}"
  extra=(); for p in $UPDATE_EXTRA; do pm -Sp "$p" >/dev/null 2>&1 && extra+=("$p") || echo "  (not in the repositories: $p)"; done
  pm --noconfirm -Su --needed "${extra[@]}"
  for p in $UPDATE_REMOVE; do pm -Q "$p" >/dev/null 2>&1 && pm --noconfirm -Rdd "$p"; done
  rm -rf $R/etc/claude-code
  # ultimate-keyring's pacman-key leaves a gpg-agent running in the copy
  chroot $R gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true
  for f in proc sys dev; do umount -R $R/$f 2>/dev/null || umount -R -l $R/$f; done
  rm -rf $R/var/lib/pacman/sync /tmp/update-cache
fi

cat > $R/etc/fstab <<'FSTAB'
# /etc/fstab -- Ultimate Linux (from source)
PARTUUID=554c5431-02  /  ext4  defaults  1  1
FSTAB

rm -f $R/etc/systemd/network/*.network
# The build tree leaves /usr/bin group-writable (775); packages say 755 and
# pacman warns on every install.
chmod 755 $R/usr/bin
if [[ -e $R/usr/lib/systemd/system/NetworkManager.service ]]; then
  # The desktop layer is built: NetworkManager owns networking (Plasma's
  # network applet talks to it); systemd-networkd would fight it.
  # Every enablement link, not just the service: its varlink/resolve-hook
  # sockets and the dbus alias socket-activate networkd again at boot.
  find $R/etc/systemd/system -lname '*systemd-networkd*' -delete
  rm -f $R/etc/systemd/system/dbus-org.freedesktop.network1.service
else
  # Base system only: any wired interface, by DHCP.
  cat > $R/etc/systemd/network/20-wired.network <<'NET'
[Match]
Name=en*

[Network]
DHCP=yes
NET
fi

cat > $R/etc/os-release <<'OS'
NAME="RedCyfer's Ultimate Linux"
PRETTY_NAME="RedCyfer's Ultimate Linux (from source)"
ID=ultimate
BUILD_ID=lfs-13.1-systemd
LOGO=ultimate-linux
HOME_URL="https://redcyfer.com/linux/"
SUPPORT_URL="https://chat.redcyfer.com/join"
BUG_REPORT_URL="https://github.com/cwoodall85/redcyfers-ultimate-linux/issues"
OS
echo ultimate > $R/etc/hostname
# DNS through systemd-resolved's stub; never a resolv.conf copied from
# the machine that built the image.
ln -sfn ../run/systemd/resolve/stub-resolv.conf $R/etc/resolv.conf

# No systemd-sysusers in this systemd: create the users packages declare.
[[ -x $R/usr/bin/ultimate-sysusers ]] && $R/usr/bin/ultimate-sysusers $R
# RELEASE=1 (make-image.sh --usb): nobody has a known password. Root is
# locked; the live session logs in by itself (below). Otherwise: known
# passwords, for the test VMs only. Never ship those.
if [[ ${RELEASE:-} == 1 ]]; then
  chroot $R usermod -p '*' root   # '*': no password works; '!' would also lock out SSH keys
else
  echo 'root:ultimate' | chroot $R chpasswd
fi
for f in .bashrc .bash_profile; do
  [[ -e $R/etc/skel/$f && ! -e $R/root/$f ]] && cp $R/etc/skel/$f $R/root/$f
done
if [[ -e $R/usr/bin/sddm ]]; then
  # A desktop user, in the groups the book's placeholder-user lines meant
  # (lpadmin for printers, netdev for networks) plus the usual ones.
  if [[ ${RELEASE:-} == 1 ]]; then comment="Live session"; else comment="Ultimate test user"; fi
  chroot $R useradd -m -s /bin/bash -c "$comment" ultimate 2>/dev/null || chroot $R usermod -c "$comment" ultimate
  for g in wheel audio video input lpadmin netdev libvirt kvm; do
    chroot $R getent group $g >/dev/null && chroot $R usermod -aG $g ultimate
  done
  if [[ ${RELEASE:-} == 1 ]]; then
    # The live session: no password, logged in at boot, allowed to run the
    # installer (and anything else as root) without asking -- like any live
    # USB. ultimate-install removes all of this from the installed system.
    chroot $R passwd -d ultimate >/dev/null
    mkdir -p $R/etc/sddm.conf.d $R/etc/polkit-1/rules.d $R/etc/sudoers.d
    printf '[Autologin]\nUser=ultimate\nSession=plasma.desktop\n' > $R/etc/sddm.conf.d/50-ultimate-live.conf
    echo 'ultimate ALL=(ALL:ALL) NOPASSWD: ALL' > $R/etc/sudoers.d/20-ultimate-live
    chmod 440 $R/etc/sudoers.d/20-ultimate-live
    cat > $R/etc/polkit-1/rules.d/49-ultimate-live.rules <<'RULES'
// The live session (ultimate-install removes this file).
polkit.addRule(function (action, subject) {
    if (subject.user == "ultimate") return polkit.Result.YES;
});
RULES
    # nothing to unlock a locked screen with
    install -d -o 1000 -g 1000 $R/home/ultimate/.config
    printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' > $R/home/ultimate/.config/kscreenlockerrc
    chroot $R chown -R ultimate:ultimate /home/ultimate/.config
  else
    echo 'ultimate:ultimate' | chroot $R chpasswd
  fi
fi
# Administrators are the wheel group, for sudo as for polkit.
if [[ -d $R/etc/sudoers.d ]]; then
  echo '%wheel ALL=(ALL:ALL) ALL' > $R/etc/sudoers.d/10-wheel
  chmod 440 $R/etc/sudoers.d/10-wheel
fi
if [[ -e $R/usr/bin/sddm ]]; then
  ln -sf /usr/lib/systemd/system/graphical.target $R/etc/systemd/system/default.target
fi

# KDE's Welcome Center would open over our own first-login Claude terminal.
# Its KDED module opens it when the user has no "last seen version" (and,
# on purpose, after a Plasma upgrade); a system-wide default of the
# installed version keeps it closed on first login.
f=$R/opt/kf6/lib/cmake/LibKWorkspace/LibKWorkspaceConfigVersion.cmake
if [[ -f $f ]]; then
  v=$(sed -n 's/^set(PACKAGE_VERSION "\([0-9.]*\)")$/\1/p' $f)
  printf '[General]\nLastSeenVersion=%s\n' "$v" > $R/etc/xdg/plasma-welcomerc
fi

# SDDM's greeter caches compiled shaders; a cache carried in from the build
# tree is stale ("Failed to deserialize QShader"). It is rebuilt on start.
rm -rf $R/var/lib/sddm/.cache

# The installer comes with the ultimate-boot package (the Ultimate layer);
# on the image, its launcher also sits on the test user's desktop.
if [[ -d $R/home/ultimate && -f $R/usr/share/applications/ultimate-install.desktop ]]; then
  install -Dm755 $R/usr/share/applications/ultimate-install.desktop $R/home/ultimate/Desktop/ultimate-install.desktop
  chroot $R chown -R ultimate:ultimate /home/ultimate/Desktop
fi

# SSH: every copy of the image must not share host keys. Drop the
# build's; sshd makes its own on first start. sshd reads a drop-in
# directory (the book's config doesn't include it).
rm -f $R/etc/ssh/ssh_host_*
grep -q '^Include /etc/ssh/sshd_config.d/' $R/etc/ssh/sshd_config ||
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' $R/etc/ssh/sshd_config
mkdir -p $R/etc/ssh/sshd_config.d $R/etc/systemd/system/sshd.service.d
printf '[Service]\nExecStartPre=/usr/bin/ssh-keygen -A\n' \
  > $R/etc/systemd/system/sshd.service.d/10-host-keys.conf
# An rsync daemon, enabled by the book's unit install, has no business
# listening on a desktop by default.
rm -f $R/etc/systemd/system/multi-user.target.wants/rsyncd.service
# Test access (TEST_SSH_KEY from make-image.sh): root by key only. The
# installer removes both files from installed systems.
if [[ -n ${TEST_SSH_KEY:-} ]]; then
  install -d -m700 $R/root/.ssh
  echo "$TEST_SSH_KEY" > $R/root/.ssh/authorized_keys
  chmod 600 $R/root/.ssh/authorized_keys
  echo 'PermitRootLogin prohibit-password' > $R/etc/ssh/sshd_config.d/90-ultimate-test.conf
fi

# The newest kernel: the image's menu has one entry.
kernel=$(cd $R/boot && ls vmlinuz-* | sort -V | tail -1)
mkdir -p $R/boot/grub/i386-pc $R/boot/grub/x86_64-efi
cp $R/usr/lib/grub/i386-pc/*.{mod,lst} $R/boot/grub/i386-pc/
cp $R/usr/lib/grub/x86_64-efi/*.{mod,lst} $R/boot/grub/x86_64-efi/
# CPU microcode, loaded by the kernel before anything else (there's no
# initramfs; each image is only the microcode). The kernel ignores the
# vendor that isn't this CPU's.
ucode=""
for u in amd-ucode.img intel-ucode.img; do
  [[ -f $R/boot/$u ]] && ucode="$ucode /boot/$u"
done
[[ -n $ucode ]] && ucode="initrd$ucode"
# Root is set by the boot image's early config (search by label).
cat > $R/boot/grub/grub.cfg <<GRUB
set default=0
set timeout=3
insmod part_msdos
insmod ext2
insmod all_video
set gfxpayload=keep
menuentry "Ultimate Linux (from source, kernel ${kernel#vmlinuz-})" {
    linux /boot/$kernel root=PARTUUID=554c5431-02 rootwait ro quiet splash plymouth.ignore-serial-consoles console=tty0 console=ttyS0,115200
    $ucode
}
GRUB
cat > $R/tmp/early.cfg <<'EARLY'
search --no-floppy --label ultimate-root --set=root
set prefix=($root)/boot/grub
EARLY

echo "== building the filesystem image"
# Room beyond the content: 30% + 2 GiB for VMs and tests; USB sticks get
# IMAGE_SLACK_PCT=7 IMAGE_EXTRA_MB=768 (make-image.sh --usb), enough for a
# live session and the installer, so the image fits a 16 GB stick.
size_mb=$(( $(du -sm $R | cut -f1) * (100 + ${IMAGE_SLACK_PCT:-30}) / 100 + ${IMAGE_EXTRA_MB:-2048} ))
rm -f /out/root.ext4
truncate -s ${size_mb}M /out/root.ext4
mkfs.ext4 -q -F -L ultimate-root -d $R /out/root.ext4

echo "== building the EFI system partition"
esp_mb=256
chroot $R grub-mkimage -O x86_64-efi -d /usr/lib/grub/x86_64-efi \
  -c /tmp/early.cfg -p /boot/grub -o /tmp/BOOTX64.EFI \
  part_msdos part_gpt ext2 fat search search_label search_fs_uuid normal
rm -f /out/esp.fat
mkfs.fat -F 32 -n ULTIMATE -C /out/esp.fat $(( esp_mb * 1024 )) >/dev/null
mmd -i /out/esp.fat ::/EFI ::/EFI/BOOT
SB=$R/usr/lib/ultimate/secureboot
if [[ -f $SB/grubx64.efi ]]; then
  # The signed chain (secureboot/sign.sh): shim as the firmware's fallback
  # loader, then our signed GRUB, which reads the grub.cfg next to it: find
  # the image's root and its menu. The certificate is at the top of the
  # partition for MokManager's "Enroll key from disk".
  printf 'search --no-floppy --label ultimate-root --set=root\nset prefix=($root)/boot/grub\nconfigfile $prefix/grub.cfg\n' > /tmp/esp-grub.cfg
  mcopy -i /out/esp.fat $SB/shimx64.efi ::/EFI/BOOT/BOOTX64.EFI
  mcopy -i /out/esp.fat $SB/grubx64.efi $SB/mmx64.efi ::/EFI/BOOT/
  mcopy -i /out/esp.fat /tmp/esp-grub.cfg ::/EFI/BOOT/grub.cfg
  mcopy -i /out/esp.fat $SB/ultimate-mok.cer ::/ultimate-mok.cer
  echo "   signed boot chain (Secure Boot)"
else
  mcopy -i /out/esp.fat $R/tmp/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
  echo "   unsigned GRUB (Secure Boot must be off)"
fi

echo "== assembling the disk"
disk=/out/ultimate-src.raw
rm -f $disk
truncate -s $(( 1 + esp_mb + size_mb + 1 ))M $disk
# Disk id 0x554c5431 ("ULT1") fixes the partition UUIDs: 554c5431-01/-02.
sfdisk -q $disk <<PT
label: dos
label-id: 0x554c5431
start=2048, size=$(( esp_mb * 2048 )), type=ef
start=$(( 2048 + esp_mb * 2048 )), type=83, bootable
PT
dd if=/out/esp.fat of=$disk bs=1M seek=1 conv=notrunc,sparse status=none
dd if=/out/root.ext4 of=$disk bs=1M seek=$(( 1 + esp_mb )) conv=notrunc,sparse status=none
rm -f /out/root.ext4 /out/esp.fat

echo "== installing GRUB (our build) into the MBR"
chroot $R grub-mkimage -O i386-pc -d /usr/lib/grub/i386-pc \
  -c /tmp/early.cfg -p /boot/grub -o /tmp/core.img \
  biosdisk part_msdos ext2 search search_label
cp $R/tmp/core.img /tmp/core.img
# boot.img's code goes before the partition table (first 440 bytes); it
# loads core.img from sector 1 by default, and core.img must fit in the
# gap before the first partition at sector 2048.
[[ $(stat -c%s /tmp/core.img) -lt $(( 2047 * 512 )) ]]
dd if=$R/usr/lib/grub/i386-pc/boot.img of=$disk bs=440 count=1 conv=notrunc status=none
dd if=/tmp/core.img of=$disk bs=512 seek=1 conv=notrunc status=none
sfdisk -l $disk
ls -lsh $disk
