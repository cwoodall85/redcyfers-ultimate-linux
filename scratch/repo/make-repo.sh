#!/bin/bash
# Build the signed package repositories that `pacman -Syu` updates from.
#
#   scratch/repo/make-repo.sh            (rerunnable; only new files are signed)
#
# Three repositories, in pacman.conf order:
#   ultimate          the Ultimate packages and everything built natively
#                     (kernel, Podman, QEMU/libvirt, voice, keyring, ...)
#   ultimate-desktop  the desktop layer (Qt, KDE Frameworks, Plasma, ...)
#   ultimate-base     the base system (LFS)
# Each package name lives in exactly one of them: pacman upgrades from the
# first repository that has a name, whatever the version, so a copy further
# down would never be seen. The layer the build installs last wins (ultimate,
# then desktop, then base), newest version within a layer: BLFS rebuilds some
# base packages (curl, systemd, dbus...), and its curl is an OLDER version
# than the base one, yet it is the one installed.
#
# Output: $OUT/<repo>/os/x86_64/ (Arch's layout, so hosting is a plain sync):
# the packages, a detached .sig for each, and <repo>.db/.files, signed.
# Old versions are removed. REPORT.txt compares the result with what is
# installed on this machine.
#
# Sources (all optional; missing ones are skipped):
#   BASE_PKGS     default: the build tree's /var/lib/packages (podman volume)
#   DESKTOP_PKGS  default: scratch/out/desktop-pkgs
#   OWN_PKGS      default: out/repo out/native/pkgs out/arch-pkgs
#                 /mnt/storage/ultimate-pkgs{,/native-virt}
#   FROM_ARCH     packages taken from Arch as-is (fonts; see
#                 container-ultimate-layer.sh), fetched into out/arch-pkgs
#   EXCLUDE       package names never published (default: google-chrome
#                 claude-code -- neither may be redistributed; Claude Code is
#                 installed from Anthropic at first login instead)
# Signing: the repository subkey in SIGN_HOME (default
# ~/.local/share/ultimate-linux/repo-signing/signer). The primary key is not
# needed here and should not be on this machine.
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:-/mnt/storage/ultimate-repo}
ARCH=x86_64
SIGN_HOME=${SIGN_HOME:-$HOME/.local/share/ultimate-linux/repo-signing/signer}
DESKTOP_PKGS=${DESKTOP_PKGS:-$here/scratch/out/desktop-pkgs}
EXCLUDE=${EXCLUDE:-google-chrome claude-code}
read -r -a own <<< "${OWN_PKGS:-$here/out/repo $here/out/native/pkgs $here/out/arch-pkgs /mnt/storage/ultimate-pkgs /mnt/storage/ultimate-pkgs/native-virt}"
FROM_ARCH=${FROM_ARCH-ttf-jetbrains-mono inter-font}
repos=(ultimate ultimate-desktop ultimate-base)

export GNUPGHOME=$SIGN_HOME
KEY=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^ssb/{s=1} s && /^fpr/{print $10; exit}')
[[ -n $KEY ]] || { echo "no signing subkey in $SIGN_HOME" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# The base packages sit in the build tree, owned by mapped uids: copy them out.
if [[ -z ${BASE_PKGS:-} ]]; then
  BASE_PKGS=$work/base
  mnt=$(podman volume inspect ultimate-lfs-build --format '{{.Mountpoint}}' 2>/dev/null || true)
  if [[ -n $mnt ]]; then
    mkdir -p "$BASE_PKGS"
    podman unshare tar -C "$mnt/var/lib/packages" -cf - . | tar -C "$BASE_PKGS" -xf - --no-same-owner
  fi
fi

# Fonts the layer takes from Arch as-is: fetch them once (a rerun keeps them).
if [[ -n $FROM_ARCH ]]; then
  mkdir -p "$here/out/arch-pkgs"
  missing=(); for p in $FROM_ARCH; do compgen -G "$here/out/arch-pkgs/$p-[0-9]*.pkg.tar.*" >/dev/null || missing+=("$p"); done
  if (( ${#missing[@]} )); then
    podman run --rm --security-opt label=disable -v "$here/out/arch-pkgs:/o" docker.io/library/archlinux:latest \
      bash -c "pacman -Sy >/dev/null && pacman -Sw --noconfirm --cachedir /o ${missing[*]} >/dev/null && chown -R $(id -u):$(id -g) /o"
  fi
fi

# 1. Candidates: "repo<TAB>path", in precedence order (a tie keeps the first).
{
  for d in "${own[@]}"; do [[ -d $d ]] && find "$d" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -printf "ultimate\t%p\n"; done
  [[ -d $DESKTOP_PKGS ]] && find "$DESKTOP_PKGS" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -printf "ultimate-desktop\t%p\n"
  [[ -d $BASE_PKGS ]] && find "$BASE_PKGS" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -printf "ultimate-base\t%p\n"
} > "$work/candidates"
[[ -s $work/candidates ]] || { echo "no packages found" >&2; exit 1; }

# 2. One copy per name: the latest layer, then the newest version (vercmp; the
#    file name can't be trusted to split name and version, so ask .PKGINFO).
while IFS=$'\t' read -r repo f; do
  meta=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | awk -F' = ' '$1=="pkgname"{n=$2} $1=="pkgver"{v=$2} END{print n"\t"v}')
  printf '%s\t%s\t%s\n' "$meta" "$repo" "$f"
done < "$work/candidates" > "$work/meta"
declare -A best_v best_repo best_f rank=([ultimate]=0 [ultimate-desktop]=1 [ultimate-base]=2)
while IFS=$'\t' read -r n v repo f; do
  [[ -n $n && -n $v ]] || { echo "skipped (no .PKGINFO): $f" >&2; continue; }
  [[ " $EXCLUDE " == *" $n "* ]] && continue
  if [[ -z ${best_v[$n]:-} ]] || (( rank[$repo] < rank[${best_repo[$n]}] )) ||
     { [[ $repo == "${best_repo[$n]}" ]] && (( $(vercmp "$v" "${best_v[$n]}") > 0 )); }; then
    best_v[$n]=$v; best_repo[$n]=$repo; best_f[$n]=$f
  fi
done < "$work/meta"

# 2b. Never publish a private key (Secure Boot MOK, repository signing key):
#     our own packages are opened and searched before anything is signed.
leak=0
for n in "${!best_v[@]}"; do
  [[ ${best_repo[$n]} == ultimate ]] || continue
  f=${best_f[$n]}
  if bsdtar -tf "$f" 2>/dev/null | grep -qiE '(\.key|secring\.gpg|private[^/]*\.(asc|gpg|pem))$' ||
     bsdtar -xOf "$f" 2>/dev/null | grep -aqE -- '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|-----BEGIN PGP PRIVATE KEY BLOCK-----'; then
    echo "REFUSING: $n ($f) contains what looks like a private key" >&2; leak=1
  fi
done
(( leak == 0 )) || exit 1

# 3. Lay the repositories out; hard links where the source is on the same disk.
for r in "${repos[@]}"; do mkdir -p "$OUT/$r/os/$ARCH"; : > "$work/keep-$r"; done
new=0
for n in "${!best_v[@]}"; do
  r=${best_repo[$n]} f=${best_f[$n]}; b=$(basename "$f"); dst=$OUT/$r/os/$ARCH/$b
  echo "$b" >> "$work/keep-$r"
  if [[ ! -e $dst ]]; then
    ln "$f" "$dst" 2>/dev/null || cp "$f" "$dst"
    rm -f "$dst.sig"; new=$((new + 1))
  fi
  if [[ ! -e $dst.sig ]]; then
    gpg --batch --quiet --detach-sign --no-armor -u "$KEY!" -o "$dst.sig" "$dst"
  fi
done

# 4. Drop what is no longer chosen, then write each database from scratch.
for r in "${repos[@]}"; do
  d=$OUT/$r/os/$ARCH
  find "$d" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -printf '%f\n' | sort > "$work/have-$r"
  sort -o "$work/keep-$r" "$work/keep-$r"
  comm -23 "$work/have-$r" "$work/keep-$r" | while read -r b; do rm -f "$d/$b" "$d/$b.sig"; done
  rm -f "$d/$r".{db,files}{,.tar.gz,.tar.gz.sig,.sig} "$d/$r".{db,files}.tar.gz.old{,.sig}
  if [[ -s $work/keep-$r ]]; then
    (cd "$d" && repo-add -q --sign --key "$KEY!" "$r.db.tar.gz" $(cat "$work/keep-$r")) 2>&1 |
      grep -v -e '^==>' -e 'WARNING: A newer version' || true
  fi
  printf '%-17s %4d packages  %s\n' "$r" "$(wc -l < "$work/keep-$r")" "$(du -sh "$d" | cut -f1)"
done
echo "$new new package files signed with $KEY"

# 5. How this machine compares.
{
  echo "Repository built $(date -Is) from $(hostname); signing subkey $KEY"
  pacman -Q | while read -r n v; do
    if [[ -z ${best_v[$n]:-} ]]; then echo "not in any repository: $n $v"
    else c=$(vercmp "$v" "${best_v[$n]}")
      (( c < 0 )) && echo "update available:      $n $v -> ${best_v[$n]} [${best_repo[$n]}]"
      (( c > 0 )) && echo "installed is newer:    $n $v (repo has ${best_v[$n]})"
    fi
    true
  done | sort
} > "$OUT/REPORT.txt"
grep -c '' "$OUT/REPORT.txt" >/dev/null; sed 1d "$OUT/REPORT.txt" | cut -c1-22 | sort | uniq -c
echo "report: $OUT/REPORT.txt"
