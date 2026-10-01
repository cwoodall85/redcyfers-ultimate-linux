#!/bin/bash
# Unattended install test. In the running ultimate-test VM, booted from the
# live ISO with a blank disk, install with the real installer config
# (/etc/ultimate/archinstall.json: KDE Plasma, SDDM, the package lists), adding
# only the disk layout, users and the guest agent, reboot into
# the installed disk, and check the promised commands are there.
#
#   NO_VIEWER=1 tools/test-vm.sh && sleep 90 && tools/test-install.sh
#
# This WIPES the VM's disk (/dev/vda). Test logins: root and "tester",
# password "ultimate".
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
vm() { python3 "$here/vm-exec.py" "$@"; }
hash=$(openssl passwd -6 ultimate)

echo "== writing the test config in the guest"
vm "python3 - <<'PY'
import json
cfg = json.load(open('/etc/ultimate/archinstall.json'))
# archinstall 4.4 needs an explicit sector size; its sample's null crashes.
SS = {'value': 512, 'unit': 'B'}
cfg.update({
  'archinstall-language': 'English',
  'bootloader_config': {'bootloader': 'Systemd-boot', 'uki': False, 'removable': False},
  'disk_config': {'config_type': 'default_layout', 'device_modifications': [{
    'device': '/dev/vda', 'wipe': True, 'partitions': [
      {'btrfs': [], 'flags': ['boot', 'esp'], 'fs_type': 'fat32', 'mount_options': [],
       'mountpoint': '/boot', 'obj_id': 'b0000000-0000-4000-8000-000000000001',
       'start': {'sector_size': SS, 'unit': 'MiB', 'value': 1},
       'size': {'sector_size': SS, 'unit': 'MiB', 'value': 1024},
       'status': 'create', 'type': 'primary', 'dev_path': None},
      {'btrfs': [], 'flags': [], 'fs_type': 'ext4', 'mount_options': [],
       'mountpoint': '/', 'obj_id': 'b0000000-0000-4000-8000-000000000002',
       'start': {'sector_size': SS, 'unit': 'MiB', 'value': 1025},
       'size': {'sector_size': SS, 'unit': 'GiB', 'value': 38},
       'status': 'create', 'type': 'primary', 'dev_path': None}]}]},
  'hostname': 'ultimate-installed',
  'kernels': ['linux'],
  'locale_config': {'kb_layout': 'us', 'sys_enc': 'UTF-8', 'sys_lang': 'en_US'},
  'ntp': True,
  'swap': {'enabled': False},
  'timezone': 'UTC',
  'services': cfg.get('services', []) + ['qemu-guest-agent'],
  'packages': cfg['packages'] + ['qemu-guest-agent'],
})
json.dump(cfg, open('/root/test-install.json', 'w'), indent=2)
json.dump({'root_enc_password': '$hash', 'users': [
  {'username': 'tester', 'enc_password': '$hash', 'sudo': True}]},
  open('/root/test-creds.json', 'w'))
print(len(cfg['packages']), 'packages')
PY"

echo "== installing (several minutes)"
vm "nohup archinstall --config /root/test-install.json --creds /root/test-creds.json --silent > /root/install.log 2>&1; echo \$? > /root/install.exit" --timeout 5 >/dev/null 2>&1 || true
for _ in $(seq 1 180); do
  if vm "test -f /root/install.exit" >/dev/null 2>&1; then break; fi
  sleep 10
done
code=$(vm "cat /root/install.exit" 2>/dev/null || echo "?")
vm "tail -15 /root/install.log"
[[ $code == 0 ]] || { echo "archinstall exited $code; full log: /var/log/archinstall/install.log in the VM" >&2; exit 1; }

echo "== rebooting into the installed system"
virsh -c qemu:///system destroy ultimate-test >/dev/null
virsh -c qemu:///system start ultimate-test >/dev/null
for _ in $(seq 1 60); do
  vm "true" >/dev/null 2>&1 && break
  sleep 5
done

echo "== checking the installed system"
vm "sleep 15; hostnamectl --static; systemctl is-active --quiet sddm && echo 'sddm login screen running' || { echo 'sddm NOT running'; exit 1; }; ultimate-mail --help >/dev/null && echo 'ultimate-mail engine starts'; missing=0
if pacman -Sy >/tmp/sync.log 2>&1 && ! grep -q error /tmp/sync.log; then echo 'pacman -Sy clean'; else cat /tmp/sync.log; missing=1; fi
for c in ifconfig netstat route arp dig whois traceroute mtr trip gping nmap arp-scan tcpdump ngrep tshark wireshark termshark iperf3 nethogs iftop bmon bandwhich nload vnstat speedtest-cli ethtool iw ipcalc curl wget nc socat rsync lsof ssh mosh sshpass wg openvpn nft conntrack doggo ultimate-mail ultimate-mail-gtk ultimate-ssh ask claude ultimate-mcp; do
  command -v \$c >/dev/null || { echo \"MISSING: \$c\"; missing=1; }
done
[ \$missing = 0 ] && echo 'all networking commands and Ultimate apps present'; exit \$missing"
