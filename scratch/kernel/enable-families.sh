#!/bin/bash
# Run in a configured kernel tree (after merge_config + olddefconfig) by
# tools/make-kernel-config.sh. Turns on whole option families listed in
# all-of.list: each unset option in a family becomes a module where it can
# be one, else built in. Per-chip options appear only once their parent is
# on, so it repeats until nothing changes; udev later loads only the modules
# a machine needs.
#
# Never turned on: debug, tracing and test options, and the developer or
# policy switches drivers hide behind the same prefixes (forcing probe modes,
# disabling features, DFS certification, IPC fault injection, ...).
set -euo pipefail
list=${1:?all-of.list}
pat=$(grep -v -e '^#' -e '^$' "$list" | paste -sd'|')
skip='DEBUG|TRACE|TEST|KUNIT|SELFTEST|NOCODEC|FORCE|STRICT|DISABLE|DEVELOPER|EXPERIMENTAL|INJECT|FLOOD|RETAIN|ALWAYS_ON|VERBOSE|DUMP|DFS_CERTIFIED|DYNACK|SPECTRAL|CHANNEL_CONTEXT|_PROBE_WORK|COMPILE_ALL|ALL_CODECS'
unset_opts() {
  grep -E "^# CONFIG_($pat) is not set$" .config | sed -E 's/^# (CONFIG_[A-Za-z0-9_]+) is not set$/\1/' |
    grep -v -E "$skip" || true
}
set_to() {  # value options...
  local v=$1 o; shift
  for o in "$@"; do sed -i "s/^# $o is not set$/$o=$v/" .config; done
}
for i in $(seq 1 8); do
  before=$(md5sum < .config)
  mapfile -t c < <(unset_opts)
  ((${#c[@]})) || break
  set_to m "${c[@]}"; make -s olddefconfig
  mapfile -t c2 < <(unset_opts)          # bools refuse "m": try them built in
  ((${#c2[@]})) && { set_to y "${c2[@]}"; make -s olddefconfig; }
  [[ $(md5sum < .config) == "$before" ]] && break
done
