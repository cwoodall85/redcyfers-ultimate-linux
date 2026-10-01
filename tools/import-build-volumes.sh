#!/bin/bash
# Bring the from-source build volumes (ultimate-lfs-build, -lfs-sources,
# ultimate-blfs-plan) from another install's rootless Podman into this one's,
# e.g. from Fedora's disk after moving to Ultimate Linux. Run as root:
#
#   sudo tools/import-build-volumes.sh <source volumes dir> <old subuid start> [user]
#   sudo tools/import-build-volumes.sh /mnt/fedora-home/cwoodall/.local/share/containers/storage/volumes 524288
#
# Rootless Podman stores container uid 0 as the user's own uid and uid N as
# subuid_start+N-1, and the two installs gave the user different subuid
# ranges, so every file owned by a non-root container user is re-owned from
# the old range to this machine's. chown clears setuid/setgid bits and file
# capabilities, so both are put back. Create the empty volumes first as the
# user (podman volume create ...).
set -euo pipefail
src=$1 old=$2 user=${3:-${SUDO_USER:-cwoodall}}
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
new=$(awk -F: -v u="$user" '$1==u{print $2}' /etc/subuid)
newg=$(awk -F: -v u="$user" '$1==u{print $2}' /etc/subgid)
[[ -n $new && $new == "$newg" ]] || { echo "no matching subuid/subgid range for $user" >&2; exit 1; }
home=$(getent passwd "$user" | cut -d: -f6)
dst=$home/.local/share/containers/storage/volumes

for v in ultimate-lfs-build ultimate-lfs-sources ultimate-blfs-plan; do
  [[ -d $src/$v/_data ]] || { echo "missing $src/$v/_data" >&2; exit 1; }
  [[ -d $dst/$v/_data ]] || { echo "create the volume first: podman volume create $v" >&2; exit 1; }
  echo "== $v ($(du -sh "$src/$v/_data" | cut -f1))"
  rsync -aHAX --numeric-ids --delete --info=stats1 "$src/$v/_data/" "$dst/$v/_data/"
  python3 - "$dst/$v/_data" "$old" "$new" <<'EOF'
import os, stat, sys
root, old, new = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
shift = lambda i: i - old + new if old <= i < old + 65536 else i
n = 0
for d, dirs, files in os.walk(root):
    for p in [d] + [os.path.join(d, f) for f in dirs + files]:
        st = os.lstat(p)
        u, g = shift(st.st_uid), shift(st.st_gid)
        if (u, g) == (st.st_uid, st.st_gid):
            continue
        link = stat.S_ISLNK(st.st_mode)
        caps = None
        if not link:
            try: caps = os.getxattr(p, "security.capability")
            except OSError: pass
        os.lchown(p, u, g)
        if not link:
            os.chmod(p, stat.S_IMODE(st.st_mode))
            if caps: os.setxattr(p, "security.capability", caps)
        n += 1
print(f"   re-owned {n} paths ({old}.. -> {new}..)")
EOF
done
echo "done"
