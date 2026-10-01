#!/bin/bash
# Runs INSIDE the build container (see ../build.sh). Prepares a jhalfs
# checkout with the distro's pacman recipe and runs the whole LFS build.
set -euo pipefail
pacman -Syu --noconfirm --needed base-devel texinfo libxslt docbook-xml docbook-xsl \
  wget git python sudo bc >/dev/null 2>&1 || pacman -Syu --noconfirm --needed base-devel texinfo \
  libxslt docbook-xml docbook-xsl wget git python sudo bc

id builder >/dev/null 2>&1 || useradd -m builder
echo 'builder ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
# jhalfs creates its own "lfs" user for the temporary tools; a stale one
# from an earlier run in the same volume would stop it.
userdel -r lfs 2>/dev/null || true

J=/home/builder/jhalfs
rm -rf "$J" && cp -r /jhalfs-src "$J"
cp /work/pkgmngt/packageManager.xml /work/pkgmngt/packInstall.sh "$J/pkgmngt/"
python3 /work/tools/write-jhalfs-config.py "$J" /work/kernel/config-7.1.8
chown -R builder "$J"
install -d -o builder /mnt/build_dir /sources-cache

# jhalfs fetches patches from the book's *development* patch directory,
# where released patches get removed (glibc-2.44-upstream_fixes-1.patch 404s
# there). Seed the cache, which jhalfs checks first, from the release's own.
rel=https://www.linuxfromscratch.org/patches/lfs/13.1
for f in $(curl -s "$rel/" | grep -oE 'href="[^"/]+\.patch"' | cut -d'"' -f2 | sort -u); do
  [[ -s /sources-cache/$f ]] || curl -sf -o "/sources-cache/$f" "$rel/$f"
done
chown -R builder /sources-cache

cd "$J"
# Generate the build (it asks one confirmation), then run the generated
# Makefile ourselves. It refuses to start without a terminal of at least
# 80x24, and a background build has none, so it runs under `script` with a
# sized pseudo-terminal.
if [[ -f /mnt/build_dir/jhalfs/Makefile && -z ${REGENERATE:-} ]]; then
  echo "Resuming the existing build (REGENERATE=1 to start over)."
else
  # Earlier steps read stdin too, so a single "yes" gets eaten; feed a
  # stream. (yes is cut off when jhalfs exits; that SIGPIPE is expected.)
  yes yes 2>/dev/null | sudo -u builder ./jhalfs run || [[ ${PIPESTATUS[1]} == 0 ]]
  [[ -f /mnt/build_dir/jhalfs/Makefile ]] || { echo "jhalfs made no Makefile" >&2; exit 1; }
fi

# Under rootless Podman, /dev/null and friends are bind mounts inside the
# container's /dev. The book's plain `mount --bind /dev` does not carry
# nested mounts, so the chroot saw empty regular files for /dev/null --
# configure scripts then read back what was "discarded" into them. Bind
# recursively, and unmount recursively.
K=/mnt/build_dir/jhalfs/kernfs-scripts
sed -i 's|mount -v --bind /dev \$LFS/dev|mount -v --rbind /dev $LFS/dev|' $K/devices.sh
sed -i 's|umount -v \$LFS/dev$|umount -v -R $LFS/dev|' $K/teardown.sh
grep -q -- '--rbind /dev' $K/devices.sh || { echo "could not patch $K/devices.sh" >&2; exit 1; }

# A resumed build runs scripts generated from an older recipe; carry recipe
# fixes into them too. curl 8.22 requires libpsl unless told otherwise.
for f in $(grep -rl -- '--with-openssl' /mnt/build_dir/jhalfs/lfs-commands/chapter0*/*-curl 2>/dev/null); do
  grep -q -- '--without-libpsl' "$f" || sed -i 's|--with-openssl|--with-openssl --without-libpsl|' "$f"
done

# The pacman recipe installs OpenSSL 4 before the book's second Python pass,
# which the book builds without OpenSSL; Python 3.14.7's _ssl then fails to
# import (OpenSSL 4 dropped TLSv1_method). Apply the book's own OpenSSL 4
# patch there too, as its final-system Python does.
for f in /mnt/build_dir/jhalfs/lfs-commands/chapter07/*-Python-pass2; do
  [[ -f $f ]] || continue
  grep -q 'openssl_4' "$f" ||
    sed -i '0,/^cd \$PKGDIR$/s||cd $PKGDIR\npatch -Np1 -i ../Python-3.14.7-openssl_4-1.patch|' "$f"
  grep -q 'openssl_4' "$f" || { echo "could not patch $f" >&2; exit 1; }
done

# Resumed builds generated before the recipe switched pkg-config to pkgconf
# have an empty package name for that step. Rewrite its source and commands.
f=/mnt/build_dir/jhalfs/lfs-commands/chapter07/713-11-pkgconfig
if [[ -f $f ]] && grep -q '^PACKAGE=$' "$f"; then
  python3 - "$f" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('PACKAGE=\n', 'PACKAGE=pkgconf-3.0.5.tar.xz\n')
s = s.replace('VERSION=""', 'VERSION="3.0.5"')
a = s.index('# Start of LFS book script\n') + len('# Start of LFS book script\n')
b = s.index('\necho -e "\\n\\nTotalseconds')
s = s[:a] + ('mkdir build\ncd    build\n'
             'meson setup --prefix=/usr --buildtype=release ..\n'
             'ninja\nninja install\nln -sfv pkgconf /usr/bin/pkg-config\n') + s[b:]
open(p, 'w').write(s)
PY
fi

# The chapter 7 shadow needs two things the old recipe predates: shadow
# 4.20 wants systemd's logind (built later) unless told otherwise, and
# glibc no longer provides crypt(), which LFS gets from libxcrypt -- built
# only in the final system. Build libxcrypt first, then shadow without
# logind. (The recipe does the same for fresh builds.)
f=/mnt/build_dir/jhalfs/lfs-commands/chapter07/713-13-shadow
if [[ -f $f ]] && ! grep -q 'libxcrypt' "$f"; then
  python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"^\./configure --sysconfdir=/etc --disable-static.*$",
           lambda m: "./configure --sysconfdir=/etc --disable-static --without-libbsd --disable-logind " + chr(92),
           s, count=1, flags=re.M)
mark = "# Start of LFS book script\n"
s = s.replace(mark, mark + "( cd .. && tar -xf libxcrypt-4.5.2.tar.xz && cd libxcrypt-4.5.2 &&\n  sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c &&\n  ./configure --prefix=/usr --enable-hashes=strong,glibc --enable-obsolete-api=no \\\n              --disable-static --disable-failure-tokens &&\n  make && make install ) && rm -rf ../libxcrypt-4.5.2\n", 1)
open(p, "w").write(s)
PY
  grep -q 'libxcrypt' "$f" && grep -q -- '--disable-logind' "$f" ||
    { echo "could not patch $f" >&2; exit 1; }
fi

# Packages are xz-compressed: zstd itself is only built partway through
# chapter 8, and makepkg can't compress with a tool that isn't there yet.
# Carry that into a chroot configured before the change.
sed -i 's/^PKGEXT=\.pkg\.tar\.zst$/PKGEXT=.pkg.tar.xz/' /mnt/build_dir/etc/makepkg.conf 2>/dev/null || true
sed -i 's/-${ARCH}\.pkg\.tar\.zst$/-${ARCH}.pkg.tar.xz/' /mnt/build_dir/jhalfs/packInstall.sh 2>/dev/null || true
rm -f /mnt/build_dir/var/lib/packages/*.pkg.tar.zst

# Under package management jhalfs points the book's gcc queries at the new
# compiler in the build tree, which doesn't know the staged install path:
# `-print-file-name=include` comes back as a bare "include" (chown fails)
# and `-print-prog-name=liblto_plugin.so` as a bare name (a dangling LTO
# plugin link). Spell out the staged paths.
f=$(ls /mnt/build_dir/jhalfs/lfs-commands/chapter08/*-gcc 2>/dev/null | head -1)
if [[ -n $f ]] && grep -q 'gcc/xgcc -print-file-name=include' "$f"; then
  gv=$(grep -m1 '^VERSION=' "$f" | cut -d'"' -f2)
  sed -i "s|^chown -v -R root:root \$(gcc/xgcc -print-file-name=include){,-fixed}$|chown -v -R root:root \$PKG_DEST/usr/lib/gcc/x86_64-pc-linux-gnu/$gv/include{,-fixed}|" "$f"
  sed -i "s|^ln -sfvr \$(gcc/xgcc -print-prog-name=liblto_plugin.so) |ln -sfv ../../libexec/gcc/x86_64-pc-linux-gnu/$gv/liblto_plugin.so |" "$f"
  if grep -q 'gcc/xgcc -print' "$f"; then echo "could not patch $f" >&2; exit 1; fi
fi

# Some tarballs record owners outside the 65536 ids a rootless container
# can map (less-704's files are uid 197609), and tar run as root fails
# trying to restore them. Nothing needs the original owners: extract every
# package as the extracting user.
sed -i 's|^tar -xf \$PACKAGE$|tar --no-same-owner -xf $PACKAGE|' \
  /mnt/build_dir/jhalfs/lfs-commands/chapter*/* 2>/dev/null || true

# The chroot's copy of packInstall.sh predates the recipe fix that installs
# whatever package makepkg actually wrote.
if ! grep -q 'Install whatever makepkg wrote' /mnt/build_dir/jhalfs/packInstall.sh 2>/dev/null &&
   [[ -f /mnt/build_dir/jhalfs/packInstall.sh ]]; then
  python3 - /mnt/build_dir/jhalfs/packInstall.sh <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'su builder -c"PATH=$PATH; makepkg -c --skipinteg" || true\n'
new = old + ('ARCHIVE_NAME=$(cd /var/lib/packages &&\n'
             '  ls -t ${PACKAGE}-${VERSION}-1-${ARCH}.pkg.tar.* 2>/dev/null | head -1)\n'
             '# Install whatever makepkg wrote\n')
assert old in s
open(p, "w").write(s.replace(old, new, 1))
PY
fi

script -qefc "stty cols 160 rows 50; sudo -u builder make -C /mnt/build_dir/jhalfs" /dev/null </dev/null
