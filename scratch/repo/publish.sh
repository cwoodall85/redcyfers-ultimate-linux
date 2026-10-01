#!/bin/bash
# Hand the signed repositories (make-repo.sh's output) to the hosting
# server, which serves them (for RedCyfer: syncs them to S3 behind a CDN).
# This machine holds no cloud credentials.
#
#   scratch/repo/publish.sh [DEST]     DEST: user@host:path (rsync over SSH)
#
# DEST and PUBLISH_SSH_KEY default to the values in
# ~/.config/ultimate-linux/publish.conf (shell assignments, never committed).
#
# Order matters to anyone updating mid-copy: new packages and signatures
# first, then the databases that point at them, then old packages go.
# DONE (a small manifest) is written last; the server syncs on its change.
set -euo pipefail
OUT=${OUT:-/mnt/storage/ultimate-repo}
conf=$HOME/.config/ultimate-linux/publish.conf
[[ -f $conf ]] && . "$conf"
DEST=${1:-${PUBLISH_DEST:-}}
[[ -n $DEST ]] || { echo "usage: publish.sh user@host:path (or PUBLISH_DEST in $conf)" >&2; exit 2; }
KEY=${PUBLISH_SSH_KEY:-$HOME/.ssh/id_ed25519}
ssh_cmd="ssh -o BatchMode=yes -i $KEY"
[[ -s $OUT/REPORT.txt ]] || { echo "no repository in $OUT (run make-repo.sh)" >&2; exit 1; }

db='*.db*'; files='*.files*'
rsync -a -e "$ssh_cmd" --exclude "$db" --exclude "$files" --exclude DONE "$OUT/" "$DEST/"
rsync -a -e "$ssh_cmd" --exclude DONE "$OUT/" "$DEST/"
rsync -a -e "$ssh_cmd" --delete --exclude DONE "$OUT/" "$DEST/"

manifest=$(mktemp); trap 'rm -f "$manifest"' EXIT
{
  echo "published $(date -Is) from $(hostname)"
  echo "commit $(git -C "$(dirname "$0")/../.." rev-parse --short HEAD 2>/dev/null || echo unknown)"
  for d in "$OUT"/*/os/x86_64; do
    r=$(basename "$(dirname "$(dirname "$d")")")
    echo "$r $(ls "$d" | grep -c '\.pkg\.tar\.[a-z]*$') packages $(sha256sum "$d/$r.db.tar.gz" | cut -d' ' -f1)"
  done
} > "$manifest"
rsync -a -e "$ssh_cmd" "$manifest" "$DEST/DONE"
cat "$manifest"
