#!/bin/bash
# xorg-env writes /etc/sudoers.d/xorg (keep XORG_PREFIX under sudo). This
# build runs as root and sudo isn't in the plan yet, so the directory
# doesn't exist. Create it; the file is right once sudo is installed.
grep -q '^mkdir -p /etc/sudoers.d$' "$1" ||
  sed -i '0,/cat > \/etc\/sudoers.d\/xorg/s||mkdir -p /etc/sudoers.d\n&|' "$1"
grep -q '^mkdir -p /etc/sudoers.d$' "$1"
