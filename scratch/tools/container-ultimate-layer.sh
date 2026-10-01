#!/bin/bash
# Runs INSIDE a container (see ../ultimate-layer.sh). Installs the Ultimate
# layer into the from-source system at /b, through ITS pacman database, so
# every file is tracked there:
#   ultimate-theme, ultimate-claude, ultimate-mail, ultimate-ssh,
#   python-imapclient  -- our packages, from out/repo (no compiled code).
#                         Not claude-code: Anthropic's installer puts it in
#                         the user's home at first login (ultimate-claude-welcome)
#   ttf-jetbrains-mono, inter-font -- font files, from Arch as-is
#   noto-fonts-emoji, noto-fonts   -- colour emoji and most of the world's
#                         scripts (no emoji font at all before: every app
#                         showed blanks); also font files from Arch as-is
# The packages name Arch's dependencies, which this system doesn't use, so
# dependency checks are off (-dd): the real dependencies come from the BLFS
# stages. Scriptlets and hooks are off too (they'd run Arch's tools against
# this root); their work -- font cache, icon and desktop databases -- is
# done below with the system's own tools.
set -euo pipefail
R=/b
# The archlinux image's pacman.conf skips man pages, docs and translations
# (NoExtract, to keep containers small); here that would strip them from
# the system being built. This container is thrown away: drop the lines.
sed -i '/^NoExtract/d' /etc/pacman.conf
pacman -Sy --noconfirm >/dev/null 2>&1
mkdir -p /tmp/fonts /tmp/nohooks
pacman -Sw --noconfirm --cachedir /tmp/fonts ttf-jetbrains-mono inter-font noto-fonts-emoji noto-fonts >/dev/null

pkgs=()
for n in ultimate-theme ultimate-claude ultimate-mail ultimate-ssh ultimate-boot python-imapclient; do
  pkgs+=("$(ls -t /repo/$n-[0-9r]*.pkg.tar.zst | head -1)")
done
pkgs+=(/tmp/fonts/ttf-jetbrains-mono-*.pkg.tar.zst /tmp/fonts/inter-font-*.pkg.tar.zst
      /tmp/fonts/noto-fonts-emoji-*.pkg.tar.zst /tmp/fonts/noto-fonts-[0-9]*.pkg.tar.zst)
printf '  %s\n' "${pkgs[@]##*/}"

pacman --root $R --dbpath $R/var/lib/pacman --cachedir /tmp/fonts \
  --hookdir /tmp/nohooks --noscriptlet --noconfirm -Udd "${pkgs[@]}"

# SDDM looks in /usr/share/sddm/themes; BLFS put Breeze under /opt/kf6.
# Our package keeps its Breeze settings (the Cognition still) in the
# /usr/share copy; link Breeze's own files in beside it.
T=$R/usr/share/sddm/themes/breeze
mkdir -p $T
for f in $R/opt/kf6/share/sddm/themes/breeze/*; do
  n=${f##*/}
  [[ $n == theme.conf.user ]] || ln -sfn "/opt/kf6/share/sddm/themes/breeze/$n" "$T/$n"
done
# BLFS writes SDDM's whole example config to /etc/sddm.conf, and SDDM reads
# that file after sddm.conf.d, so its empty settings ("Current=", the
# auto-login "User=" and "Session=", ...) override every drop-in. An empty
# value means the default anyway: drop them all.
sed -i '/^[A-Za-z]*=$/d' $R/etc/sddm.conf
# The greeter doesn't read /etc/profile, so it can't find the QML modules
# and plugins BLFS installed under /opt (Breeze needs Kirigami): "module
# org.kde.kirigami is not installed". Give it the paths.
env="QML2_IMPORT_PATH=/opt/kf6/lib/qml:/opt/qt6/qml,QT_PLUGIN_PATH=/opt/kf6/lib/plugins:/opt/qt6/plugins,XDG_DATA_DIRS=/usr/share:/opt/kf6/share"
if grep -q '^GreeterEnvironment=' $R/etc/sddm.conf; then
  sed -i "s|^GreeterEnvironment=.*|GreeterEnvironment=$env|" $R/etc/sddm.conf
else
  sed -i "s|^\[General\]$|[General]\nGreeterEnvironment=$env|" $R/etc/sddm.conf
fi

# A real /dev, /proc and /sys for the checks: Claude Code (a Bun binary)
# aborts without /dev/null and /dev/urandom. Recursive bind for /dev: under
# rootless Podman a plain bind leaves /dev/null a regular file.
mountpoint -q $R/dev || mount --rbind /dev $R/dev
mountpoint -q $R/proc || mount -t proc proc $R/proc
mountpoint -q $R/sys || mount --rbind /sys $R/sys
trap 'umount -R $R/sys $R/proc $R/dev 2>/dev/null || true' EXIT
# Arch's font packages enable their fontconfig rules from conf.default/,
# which Arch's fontconfig reads and this one doesn't: link them in.
for f in $R/usr/share/fontconfig/conf.default/*.conf; do
  [[ -e $f ]] && ln -sfn "/usr/share/fontconfig/conf.avail/${f##*/}" "$R/etc/fonts/conf.d/${f##*/}"
done
chroot $R fc-cache -f >/dev/null 2>&1 || echo "fc-cache failed"
chroot $R update-desktop-database -q /usr/share/applications 2>/dev/null || true
chroot $R gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true

echo "== checks"
chroot $R /usr/bin/claude --version
chroot $R /usr/bin/python3 -c "import ultimate_claude, imapclient; print('python packages import')"
printf '{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n' | chroot $R /usr/bin/ultimate-mcp | head -c 120; echo
chroot $R pacman -Q ultimate-theme ultimate-claude ultimate-mail ultimate-ssh ultimate-boot ttf-jetbrains-mono inter-font noto-fonts-emoji noto-fonts
chroot $R fc-match emoji | grep -q 'Noto Color Emoji' && echo 'emoji: Noto Color Emoji'
