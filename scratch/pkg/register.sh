#!/bin/bash
# Record packages as installed in the build tree's pacman database without
# touching their files (they are already there: the build put them there).
# Runs in an Arch container with the build tree at /b.
#   register.sh <package files...>
set -euo pipefail
mkdir -p /tmp/nohooks
pacman --root /b --dbpath /b/var/lib/pacman --hookdir /tmp/nohooks \
  -U --dbonly -dd --noscriptlet --noconfirm "$@" >/tmp/register.log 2>&1 ||
  { tail -20 /tmp/register.log; exit 1; }
grep -E "^(warning|error)" /tmp/register.log | grep -v "database file for" | sort | uniq -c | head -20 || true
echo "registered $# packages; $(ls /b/var/lib/pacman/local | grep -vc ALPM_DB_VERSION) in the database"
echo "== files listed but missing:"
pacman --root /b --dbpath /b/var/lib/pacman -Qk 2>/dev/null | grep -v " 0 missing files" | head -10 || true
echo "== dependency check:"
pacman --root /b --dbpath /b/var/lib/pacman -Dk 2>&1 | grep -v "database file for" | head -20
