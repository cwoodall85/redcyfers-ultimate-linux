#!/bin/bash
# Test the from-source image end to end, unattended, in libvirt/KVM:
#
#   1. the image boots (UEFI) and is healthy: systemd running, no failed
#      units, the login screen up, the tools and apps present, sound;
#   2. a desktop session starts (auto-login for the test only): KWin,
#      Plasma, the Ultimate layout (Cognition wallpaper, Claude bar), the
#      first-login Claude step in Ultimate SSH; Ultimate Mail starts;
#   3. an update: a newer package in a repository, installed by pacman -Syu;
#      every package's files present, every dependency known;
#   4. ultimate-install puts it on a second disk, unattended;
#   5. the installed disk boots under UEFI with the new account, the test
#      account gone, the EFI partition mounted, and a desktop session;
#   6. the installed disk boots under BIOS;
#   7. dual boot, Secure Boot on (when the image is signed): installed next to
#      a Fedora-like disk (its partition and EFI files must not change), then
#      reinstalled over itself, then booted by its own firmware entry.
#
#   scratch/test-image.sh                 test out/ultimate-src.qcow2
#   IMG=/path/image.qcow2 scratch/test-image.sh
#
# The image must have been made with TEST_SSH_KEY set to the public half of
# TEST_KEY (default ~/.ssh/id_ed25519), which lets root in over SSH. The test
# runs on a copy (the image is never changed) in its own VM, "ultimate-ci".
# Results: one "ok"/"not ok" line per check, screenshots and a summary in
# OUT (default scratch/out/test-<time>); exit status 1 if anything failed.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export LIBVIRT_DEFAULT_URI=qemu:///system
IMG=${IMG:-$here/out/ultimate-src.qcow2}
TEST_KEY=${TEST_KEY:-$HOME/.ssh/id_ed25519}
UPDATE_REPO=${UPDATE_REPO:-$here/out/desktop-pkgs}
OUT=${OUT:-$here/out/test-$(date -u +%Y%m%dT%H%M%SZ)}
VM=ultimate-ci
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
[[ -f $IMG ]] || { echo "no image at $IMG" >&2; exit 2; }
[[ -f $TEST_KEY ]] || { echo "no test key at $TEST_KEY" >&2; exit 2; }
[[ -e /dev/kvm ]] || { echo "no /dev/kvm: the test VMs need KVM" >&2; exit 2; }

exec > >(tee -a "$OUT/test.log") 2>&1
pass=0 fail=0 todo=0
ok()     { pass=$((pass + 1)); echo "ok      $*"; }
not_ok() { fail=$((fail + 1)); echo "not ok  $*"; }
phase()  { echo; echo "== $*  $(date -u +%H:%M:%S)"; }

ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
          -o ConnectTimeout=5 -o BatchMode=yes -i "$TEST_KEY")
IP=
on() { ssh "${ssh_opts[@]}" "root@$IP" "$@"; }
# check "description" 'remote shell command that succeeds when all is well'
check() {
  local what=$1 cmd=$2 got
  if got=$(on "$cmd" 2>&1); then ok "$what"; else not_ok "$what"; echo "$got" | tail -5 | sed 's/^/          /'; fi
}

cleanup() {
  virsh destroy $VM >/dev/null 2>&1 || true
  virsh undefine --nvram $VM >/dev/null 2>&1 || virsh undefine $VM >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The test works on copies: the image under test is never written.
work=$OUT/disks
mkdir -p "$work"
qemu-img create -q -f qcow2 -F qcow2 -b "$(readlink -f "$IMG")" "$work/image.qcow2"
qemu-img create -q -f qcow2 "$work/target.qcow2" 40G
# libvirt's QEMU user must read the image behind the copy (test-vm.sh grants
# the copy itself).
quser=$(id -un qemu 2>/dev/null || id -un libvirt-qemu 2>/dev/null || true)
if [[ -n $quser && $(id -u) != 0 ]]; then
  setfacl -m "u:$quser:r" "$(readlink -f "$IMG")"
  p=$(dirname "$(readlink -f "$IMG")")
  while [[ $p != "$HOME" && $p != / ]]; do setfacl -m "u:$quser:x" "$p" 2>/dev/null || true; p=$(dirname "$p"); done
fi

boot() {  # boot <label> [test-vm.sh options...]: start the VM, wait for SSH
  local label=$1; shift
  cleanup
  VM_NAME=$VM IMG="$work/image.qcow2" TGT="${BOOT_TGT:-$work/target.qcow2}" NO_VIEWER=1 \
    "$here/test-vm.sh" "$@" >/dev/null || { not_ok "$label: VM starts"; return 1; }
  wait_up "$label"
}
wait_up() {  # wait_up <label>: the VM's address, SSH, and start-up settled
  local label=$1 i
  IP=
  for i in $(seq 1 60); do
    IP=$(virsh domifaddr $VM 2>/dev/null | awk '/ipv4/{sub("/.*","",$4); print $4; exit}')
    [[ -n $IP ]] && break; sleep 5
  done
  [[ -n $IP ]] || { not_ok "$label: gets an address"; return 1; }
  for i in $(seq 1 60); do on true 2>/dev/null && break; sleep 5; done
  on true 2>/dev/null || { not_ok "$label: SSH answers"; return 1; }
  # "running" once start-up has settled (or "degraded" if a unit failed)
  for i in $(seq 1 40); do
    case $(on systemctl is-system-running 2>/dev/null) in running|degraded) break ;; esac
    sleep 3
  done
  ok "$label: boots, SSH at $IP"
}
# todo "description" 'command' "why": a check that is expected to fail until
# known work lands; reported, not counted as a failure.
check_todo() {
  if on "$2" >/dev/null 2>&1; then ok "$1"; else todo=$((todo + 1)); echo "todo    $1  ($3)"; fi
}
shot() {  # screenshot <name>
  virsh screenshot $VM "$OUT/$1.ppm" >/dev/null 2>&1 || return 0
  command -v magick >/dev/null && magick "$OUT/$1.ppm" "$OUT/$1.png" && rm -f "$OUT/$1.ppm"
  return 0
}
healthy() {  # healthy <label>
  check "$1: systemd running, no failed units" \
    'test "$(systemctl is-system-running)" = running || { systemctl --failed --no-legend; false; }'
  check "$1: login screen (SDDM) up" 'systemctl is-active -q sddm && pgrep -f sddm-greeter >/dev/null'
}
# A desktop session for USER through SDDM auto-login, configured for the
# test only and removed again (so an install doesn't copy it). SDDM logs in
# automatically only when it starts at boot, so this reboots.
reboot_wait() {
  on 'systemctl reboot' >/dev/null 2>&1; sleep 15
  local i
  for i in $(seq 1 60); do
    IP=$(virsh domifaddr $VM 2>/dev/null | awk '/ipv4/{sub("/.*","",$4); print $4; exit}')
    [[ -n $IP ]] && on true 2>/dev/null && return 0
    sleep 5
  done
  return 1
}
desktop() {  # desktop <label> <user>
  local label=$1 user=$2 i
  on "printf '[Autologin]\nUser=$user\nSession=plasma.desktop\n' > /etc/sddm.conf.d/99-test-autologin.conf"
  reboot_wait || { not_ok "$label: comes back after reboot"; return 1; }
  for i in $(seq 1 60); do on "pgrep -u $user -x plasmashell >/dev/null" 2>/dev/null && break; sleep 3; done
  sleep 20   # let the first-login layout and autostart settle
  check "$label: KWin and Plasma running for $user" "pgrep -u $user -x kwin_wayland >/dev/null && pgrep -u $user -x plasmashell >/dev/null"
  check "$label: Cognition wallpaper and Claude bar in the layout" \
    "for i in \$(seq 1 30); do grep -q org.ultimatelinux.cognition ~$user/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null && grep -q org.ultimatelinux.claudebar ~$user/.config/plasma-org.kde.plasma.desktop-appletsrc && exit 0; sleep 2; done; exit 1"
  check "$label: first-login Claude step open in Ultimate SSH" "pgrep -u $user -f 'ultimate_ssh.py --title Claude' >/dev/null"
  check "$label: KDE Welcome Center stays closed" "! pgrep -u $user -x plasma-welcome >/dev/null"
  shot "$label-desktop"
  on "rm -f /etc/sddm.conf.d/99-test-autologin.conf"
}
session_env() {  # the environment of USER's Plasma session, as env assignments
  on "tr '\0' '\n' < /proc/\$(pgrep -u $1 -x plasmashell | head -1)/environ | grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_DATA_DIRS|XDG_CONFIG_DIRS|PATH|HOME|LANG|QT_PLUGIN_PATH|QML2_IMPORT_PATH)=' | tr '\n' ' '"
}

# ---------------------------------------------------------------------------
phase "1. the image, UEFI"
if boot image --uefi --target-disk; then
  healthy image
  check "image: UEFI boot" 'test -d /sys/firmware/efi'
  check "image: CPU microcode images passed by GRUB" 'grep -q initrd /boot/grub/grub.cfg && test -s /boot/amd-ucode.img && test -s /boot/intel-ucode.img'
  check "image: firmware installed (GPU, Wi-Fi, SOF, regdb)" \
    'test -d /usr/lib/firmware/amdgpu && test -d /usr/lib/firmware/ath12k && test -d /usr/lib/firmware/intel/sof-ipc4 && test -f /usr/lib/firmware/regulatory.db'
  check "image: sound card" 'grep -q "^ *0 \[" /proc/asound/cards'
  check "image: apps and tools present" \
    'for t in ultimate-mail-gtk ultimate-ssh ultimate-claude-bar ask ultimate-install ultimate-migrate sudo cryptsetup openvpn nmap tcpdump mtr iftop socat wg nft ngrep dig whois tshark iperf3 ethtool rsync lsof iw aplay; do command -v $t >/dev/null || { echo "missing $t"; exit 1; }; done'
  check "image: GTK 4, libadwaita, WebKitGTK, VTE and imapclient load" \
    "python3 -c 'import gi, imapclient
for ns, v in ((\"Gtk\", \"4.0\"), (\"Adw\", \"1\"), (\"WebKit\", \"6.0\"), (\"Vte\", \"3.91\"), (\"Secret\", \"1\")):
    gi.require_version(ns, v); __import__(\"gi.repository.\" + ns)'"
  check "image: pacman knows every dependency (pacman -Dk)" 'pacman -Dk'
  shot image-login
  desktop image ultimate
  env=$(session_env ultimate)
  if [[ $env == *WAYLAND_DISPLAY=* ]]; then
    check "image: Ultimate Mail starts and stays up" \
      "sudo -u ultimate env $env setsid ultimate-mail-gtk >/tmp/um.log 2>&1 </dev/null & sleep 15; pgrep -u ultimate -f ultimate-mail-gtk >/dev/null"
  else
    not_ok "image: Ultimate Mail starts (no desktop session to start it in)"
  fi
  shot image-mail
  on "pkill -u ultimate -f [u]ltimate-mail-gtk; true"

  phase "2. an update through pacman"
  # A newer release of a small package in a repository, the way updates will
  # arrive: pacman -Syu must pick it up and install its files.
  if [[ -d $UPDATE_REPO ]] && ls "$UPDATE_REPO"/xkill-*.pkg.tar.zst >/dev/null 2>&1; then
    rm -rf "$work/repo" && mkdir -p "$work/repo"
    podman run --rm --security-opt label=disable -v "$UPDATE_REPO:/in:ro" -v "$work/repo:/r" \
      docker.io/library/archlinux:latest bash -c '
        set -e; f=$(ls /in/xkill-*.pkg.tar.zst | head -1); d=$(mktemp -d); cd $d
        bsdtar -xpf $f
        v=$(sed -n "s/^pkgver = \(.*\)-\([0-9]*\)$/\1-\2/p" .PKGINFO)
        nv=${v%-*}-$(( ${v##*-} + 1 ))
        sed -i "s/^pkgver = .*/pkgver = $nv/" .PKGINFO
        bsdtar -cf /r/xkill-$nv-x86_64.pkg.tar.zst --zstd --numeric-owner .PKGINFO .MTREE usr $(ls -d etc opt 2>/dev/null)
        repo-add -q /r/ultimate-test.db.tar.gz /r/*.pkg.tar.zst' >/dev/null 2>&1
    scp -q "${ssh_opts[@]}" -r "$work/repo" "root@$IP:/var/cache/ultimate-test-repo"
    check "update: pacman -Syu installs the newer release" '
      printf "\n[ultimate-test]\nSigLevel = Never\nServer = file:///var/cache/ultimate-test-repo\n" >> /etc/pacman.conf
      old=$(pacman -Q xkill | cut -d" " -f2)
      pacman -Syu --noconfirm >/tmp/syu.log 2>&1 || { tail -15 /tmp/syu.log; exit 1; }
      new=$(pacman -Q xkill | cut -d" " -f2)
      echo "xkill $old -> $new"; test "$old" != "$new"
      pacman -Qk xkill | grep -q " 0 missing files" && test -x /usr/bin/xkill'
    # leave the machine as it was for the install below
    on 'sed -i "/^\[ultimate-test\]/,+2d" /etc/pacman.conf; rm -rf /var/cache/ultimate-test-repo; pacman -Sy >/dev/null 2>&1; true'
  else
    todo=$((todo + 1)); echo "todo    update: pacman -Syu  (no desktop packages in $UPDATE_REPO)"
  fi
  check "image: every package's files present (pacman -Qk)" '! pacman -Qk 2>/dev/null | grep -v " 0 missing files"'

  phase "3. install to the second disk"
  check "install: ultimate-install finishes" \
    'UI_MODE=whole UI_DISK=/dev/vdb UI_USER=tester UI_FULLNAME="CI Tester" UI_PASSWORD=ci-pass-1 UI_ROOT_PASSWORD=ci-root-1 UI_HOSTNAME=ci-box UI_YES=1 UI_KEEP_TEST_ACCESS=1 ultimate-install >/tmp/install.log 2>&1 || { tail -20 /tmp/install.log; false; }'
  on 'cat /tmp/install.log' > "$OUT/install.log" 2>/dev/null
  on poweroff >/dev/null 2>&1; sleep 5
fi

# ---------------------------------------------------------------------------
phase "4. the installed disk, UEFI"
if boot installed-uefi --uefi --installed; then
  healthy installed-uefi
  check "installed-uefi: host name, account, groups" \
    'test "$(hostname)" = ci-box && id tester | grep -q "(wheel)"'
  check "installed-uefi: test account removed" '! getent passwd ultimate >/dev/null'
  check "installed-uefi: EFI partition mounted, fallback loader present" \
    'findmnt -n /boot/efi >/dev/null && test -f /boot/efi/EFI/BOOT/BOOTX64.EFI'
  check "installed-uefi: root by UUID in fstab, machine id regenerated" \
    'grep -q "^UUID=.* / " /etc/fstab && ! grep -q uninitialized /etc/machine-id'
  check "installed-uefi: the image's desktop shortcut not carried over" '! ls /home/*/Desktop/ultimate-install.desktop 2>/dev/null'
  desktop installed-uefi tester
  on poweroff >/dev/null 2>&1; sleep 5
fi

# ---------------------------------------------------------------------------
phase "5. the installed disk, BIOS"
if boot installed-bios --installed; then
  healthy installed-bios
  check "installed-bios: BIOS boot" '! test -d /sys/firmware/efi'
fi

# ---------------------------------------------------------------------------
phase "7. dual boot next to Fedora, Secure Boot on"
if [[ ! -f $here/out/ovmf-vars-ultimate.qcow2 ]]; then
  todo=$((todo + 1)); echo "todo    dual boot  (no Secure Boot test variables: secureboot/make-test-vars.sh)"
elif ! qemu-img info "$IMG" >/dev/null 2>&1; then
  not_ok "dual boot: image readable"
else
  [[ -f $here/out/fake-fedora.qcow2 ]] || "$here/secureboot/make-fake-fedora-disk.sh" "$here/out/fake-fedora.qcow2" >/dev/null
  cp "$here/out/fake-fedora.qcow2" "$work/fedora.qcow2"
  if BOOT_TGT=$work/fedora.qcow2 boot dualboot --secureboot --existing-target; then
    check "dualboot: the image boots with Secure Boot on" 'dmesg | grep -q "Secure boot enabled"'
    check "dualboot: the image carries the signed boot chain" 'test -f /usr/lib/ultimate/secureboot/grubx64.efi'
    on 'sha256sum /dev/vdb2 > /root/fedora.sum; mkdir -p /mnt/e; mount /dev/vdb1 /mnt/e; (cd /mnt/e && find EFI -type f | sort | xargs sha256sum) > /root/esp.sum; umount /mnt/e'
    inst='UI_USER=chris UI_FULLNAME="CI Dual" UI_PASSWORD=ci-pass-1 UI_ROOT_PASSWORD=ci-root-1 UI_HOSTNAME=ci-dual UI_YES=1 UI_KEEP_TEST_ACCESS=1'
    fedora_same='sha256sum -c --quiet /root/fedora.sum && mount /dev/vdb1 /mnt/e && (cd /mnt/e && sha256sum -c --quiet /root/esp.sum); r=$?; umount /mnt/e; exit $r'
    check "dualboot: install alongside, in the free space" "UI_MODE=alongside UI_DISK=/dev/vdb $inst ultimate-install >/tmp/i1.log 2>&1 || { tail -15 /tmp/i1.log; false; }"
    check "dualboot: Fedora's partition and EFI files unchanged" "$fedora_same"
    check "dualboot: firmware entry \"Ultimate Linux\" first, via shim" \
      'n=$(efibootmgr | sed -n "s/^BootOrder: \([0-9A-F]*\).*/\1/p"); efibootmgr | grep "^Boot$n" | grep -q "Ultimate Linux.*shimx64.efi"'
    # a reinstall happens from a fresh start of the install medium
    reboot_wait || not_ok "dualboot: image comes back for the reinstall"
    check "dualboot: reinstall over it" "UI_MODE=reinstall $inst ultimate-install >/tmp/i2.log 2>&1 || { tail -15 /tmp/i2.log; false; }"
    check "dualboot: Fedora still unchanged after the reinstall" "$fedora_same"
    on poweroff >/dev/null 2>&1; sleep 8
    # the install medium out: the firmware boots its own entry
    virsh detach-disk $VM vda --config >/dev/null 2>&1
    virsh start $VM >/dev/null 2>&1
    if wait_up dualboot-installed; then
      healthy dualboot-installed
      check "dualboot-installed: booted by its firmware entry, Secure Boot on" \
        'dmesg | grep -q "Secure boot enabled" && efibootmgr | grep "^Boot$(efibootmgr | sed -n "s/^BootCurrent: //p")" | grep -q "Ultimate Linux"'
      check "dualboot-installed: menu offers Fedora (its own GRUB) and firmware settings" \
        'grep -q "chainloader /EFI/fedora/grubx64.efi" /boot/efi/EFI/ultimate/grub.cfg && grep -q fwsetup /boot/efi/EFI/ultimate/grub.cfg'
      check "dualboot-installed: Fedora's data readable" 'mount -o ro /dev/vda2 /mnt && grep -q "must survive" /mnt/home/chris/MARKER; r=$?; umount /mnt; exit $r'
      on 'sha256sum /dev/vda2 > /root/fedora-before-migrate.sum'
      check "migrate: shows its plan, changes nothing" \
        'ultimate-migrate --user chris > /tmp/m0.log 2>&1 && grep -q "SSH keys" /tmp/m0.log && ! test -e /home/chris/.ssh/id_test || { cat /tmp/m0.log; false; }'
      check "migrate --apply: home files, network, module option, data mount" \
        'ultimate-migrate --user chris --apply > /tmp/m1.log 2>&1 || { tail -15 /tmp/m1.log; exit 1; }
         test "$(cat /home/chris/.ssh/id_test)" = fake-key-for-tests && test "$(stat -c %U /home/chris/.ssh/id_test)" = chris
         test "$(stat -c %a /etc/NetworkManager/system-connections/TestWiFi.nmconnection)" = 600
         grep -q fnmode=2 /etc/modprobe.d/hid_apple.conf
         grep -q " /mnt/storage " /etc/fstab && ! grep " /mnt/storage " /etc/fstab | grep -q context='
      check "dualboot-installed: Fedora still unchanged after the migration" 'sha256sum -c --quiet /root/fedora-before-migrate.sum'
    fi
  fi
fi

echo
echo "== $pass passed, $fail failed, $todo to do  (log, screenshots: $OUT)"
printf 'passed\t%s\nfailed\t%s\ntodo\t%s\n' $pass $fail $todo > "$OUT/summary"
# keep the disks when something failed, for a look
[[ $fail == 0 ]] && rm -rf "$work"
[[ $fail == 0 ]]
