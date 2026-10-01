#!/bin/bash
# Run on the build tree (/b) before packaging. Corrections that make the
# desktop layer's files belong to the right package.
set -euo pipefail
B=${1:-/b}
# BLFS appends the Qt and KF6 library paths to glibc's own /etc/ld.so.conf.
# A glibc update would write its file back and lose them (the desktop would
# no longer start). Give each its own file in /etc/ld.so.conf.d (owned by
# qt6 and kf6-intro, see attribute.py's MANUAL) and include that directory.
conf=$B/etc/ld.so.conf
mkdir -p $B/etc/ld.so.conf.d
if grep -q '^# Begin Qt addition' $conf; then
  printf '# Qt 6 (BLFS)\n/opt/qt6/lib\n' > $B/etc/ld.so.conf.d/qt6.conf
  sed -i '/^# Begin Qt addition/,/^# End Qt addition/d' $conf
fi
if grep -q '^# Begin KF6 addition' $conf; then
  printf '# KDE Frameworks 6 (BLFS)\n/opt/kf6/lib\n' > $B/etc/ld.so.conf.d/kf6.conf
  sed -i '/^# Begin KF6 addition/,/^# End KF6 addition/d' $conf
fi
grep -q '^include /etc/ld.so.conf.d/\*.conf' $conf || echo 'include /etc/ld.so.conf.d/*.conf' >> $conf
sed -i '/^$/N;/^\n$/D' $conf     # squeeze the blank lines left behind
chroot $B /usr/sbin/ldconfig 2>/dev/null || ldconfig -r $B
cat $conf
