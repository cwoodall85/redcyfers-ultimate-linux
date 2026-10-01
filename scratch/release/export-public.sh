#!/bin/bash
# Make the public copy of a repository: the current tree minus private
# files (PUBLIC-EXCLUDE in the repository's root, one git pathspec per line),
# as ONE commit with no history, on the local branch "public". Nothing is
# pushed: check the branch, then push it yourself, e.g.
#   git push <public-remote> public:main
#
#   scratch/release/export-public.sh [REPO]     default: this repository
#
# It refuses if anything private is left: PRIVATE_PATTERNS (default
# ~/.config/ultimate-linux/private-patterns, never committed) holds one
# extended regex per line -- hosts, networks, accounts, names.
set -euo pipefail
repo=$(cd "${1:-$(dirname "$0")/../..}" && git rev-parse --show-toplevel)
cd "$repo"
[[ -z $(git status --porcelain) ]] || { echo "$repo has uncommitted changes" >&2; exit 1; }
patterns=${PRIVATE_PATTERNS:-$HOME/.config/ultimate-linux/private-patterns}
[[ -s $patterns ]] || { echo "no private patterns in $patterns: refusing to guess" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git archive HEAD | tar -x -C "$work"
if [[ -f PUBLIC-EXCLUDE ]]; then
  while read -r p; do
    [[ -z $p || $p == \#* ]] && continue
    rm -rf "${work:?}/$p"
  done < PUBLIC-EXCLUDE
fi
rm -f "$work/PUBLIC-EXCLUDE"

if hits=$(grep -rnaE -f <(grep -v '^#' "$patterns" | grep .) "$work" | sed "s#^$work/##"); [[ -n $hits ]]; then
  echo "REFUSING: private references left:" >&2
  echo "$hits" | cut -c1-200 >&2
  exit 1
fi

export GIT_INDEX_FILE=$work.index
git --work-tree="$work" add -A .
tree=$(git write-tree)
rm -f "$GIT_INDEX_FILE"
msg="RedCyfer's Ultimate Linux -- public source, $(date -u +%Y-%m-%d) (from $(git rev-parse --short HEAD))"
# The public commit's identity: PUBLIC_AUTHOR="Name <email>", by default the
# project's, so no personal address lands in the public history.
author=${PUBLIC_AUTHOR:-"RedCyfer's Ultimate Linux <noreply@redcyfer.com>"}
name=${author% <*}; email=${author##*<}; email=${email%>}
commit=$(GIT_AUTHOR_NAME=$name GIT_AUTHOR_EMAIL=$email GIT_COMMITTER_NAME=$name GIT_COMMITTER_EMAIL=$email \
  GIT_AUTHOR_DATE=$(date -u +%FT%TZ) GIT_COMMITTER_DATE=$(date -u +%FT%TZ) git commit-tree "$tree" -m "$msg")
git branch -f public "$commit"
echo "branch public = $commit ($(git ls-tree -r --name-only "$commit" | wc -l) files), from $(git rev-parse --short HEAD)"
