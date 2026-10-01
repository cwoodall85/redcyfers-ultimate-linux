#!/bin/bash
# Will Ultimate Linux's kernel drive this machine? Run on the machine (its
# current OS, with its drivers loaded): every module it has loaded is mapped
# to the kernel options that build it and checked against our config.
#
#   scratch/tools/check-host-drivers.sh [kernel-config]
#
# Prints the modules our kernel lacks, plus the hardware list and Secure Boot
# state for the report. Needs podman and the build volume (for the kernel
# source); run it where the build lives, or copy lsmod output there.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cfg=${1:-$here/kernel/config-7.1.8}
ver=$(sed -n 's/^# Linux\/x86 \([0-9.]*\) Kernel Configuration$/\1/p' "$cfg" | head -1)
ver=${ver:-7.1.8}
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
lsmod | awk 'NR>1{print $1}' | sort > "$w/modules"
cp "$cfg" "$w/config"; cp "$here/tools/module-options.py" "$w/"
podman run --rm --security-opt label=disable -v ultimate-lfs-build:/b:ro -v "$w:/w" \
  docker.io/library/archlinux:latest bash -c "
  pacman -Sy --noconfirm --needed python >/dev/null 2>&1
  cd /tmp && tar -xJf /b/sources/linux-$ver.tar.xz
  python3 /w/module-options.py /tmp/linux-$ver /w/modules /w/config" > "$w/result"
echo "== $(hostname): $(wc -l < "$w/modules") modules loaded; against $(basename "$cfg")"
cut -f1 "$w/result" | sort | uniq -c
grep -v '^ok' "$w/result" || true
echo
echo "== devices and their drivers"
lspci -k | awk '/^[0-9a-f]/{d=$0} /Kernel driver in use/{print "  " $NF "\t" substr(d, 9, 90)}' | sort -u
echo
echo "== firmware"
[[ -d /sys/firmware/efi ]] && echo "  UEFI" || echo "  BIOS"
command -v mokutil >/dev/null && echo "  $(mokutil --sb-state 2>/dev/null | head -1)" || true
