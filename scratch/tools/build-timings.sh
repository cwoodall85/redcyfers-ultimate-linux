#!/bin/bash
# Per-package build times from what a finished build left behind, as one TSV
# (scratch/out/timings/<label>.tsv). For builds from before blfs/driver.sh
# logged its own times (it now writes /blfs/timings.tsv as it goes).
#
#   scratch/tools/build-timings.sh fedora-32core
#
# Columns: track stage step package seconds start_utc end_utc jobs source
#   base (LFS, jhalfs):  jhalfs's own "Totalseconds" per package -- exact.
#   blfs stages:         a log's birth time to its last write. A package
#                        built more than once (a failure, then a resume)
#                        starts at its last "== [n/N] name HH:MM" line in the
#                        driver's own logs instead -- approximate, to the
#                        minute; source says which.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
label=${1:?label, e.g. fedora-32core}
mkdir -p "$here/out/timings"
raw=$(mktemp)
podman run --rm -v ultimate-lfs-build:/b:ro docker.io/library/archlinux:latest bash -c '
  for f in /b/jhalfs/logs/[0-9]*; do
    s=$(grep -m1 -o "^Totalseconds: [0-9]*" "$f" | cut -d" " -f2)
    printf "jhalfs\t%s\t%s\t%s\n" "${f##*/}" "${s:-}" "$(stat -c %Y "$f")"
  done
  for d in /b/blfs/done /b/blfs/done-*; do
    st=${d##*/done}; st=${st#-}; st=${st:-1}
    for m in "$d"/*; do
      n=${m##*/}; l=/b/blfs/logs/$n.log
      [[ -f $l ]] && printf "blfs\t%s\t%s\t%s\t%s\n" "$st" "$n" "$(stat -c %W "$l")" "$(stat -c %Y "$l")"
    done
  done' > "$raw"
python3 - "$raw" "$here/out" "$here/out/timings/$label.tsv" <<'PY'
import datetime as dt, glob, os, re, sys
raw, outdir, dest = sys.argv[1:]
utc = dt.timezone.utc
def iso(t): return dt.datetime.fromtimestamp(t, utc).strftime("%Y-%m-%dT%H:%M:%SZ")
# driver start lines, all runs: name -> list of (HH, MM)
starts = {}
for log in glob.glob(os.path.join(outdir, "blfs-build*.log")):
    for m in re.finditer(r"^== \[\d+/\d+\] (\S+)\s+(\d\d):(\d\d)$", open(log, errors="replace").read(), re.M):
        starts.setdefault(m.group(1), []).append((int(m.group(2)), int(m.group(3))))
rows = []
for line in open(raw):
    f = line.rstrip("\n").split("\t")
    if f[0] == "jhalfs":
        name, secs, end = f[1], f[2], int(f[3])
        if not secs:
            continue
        m = re.match(r"(\d+)-(.+)", name)
        step, pkg = (m.group(1), m.group(2)) if m else ("", name)
        rows.append(("base", "lfs", step, pkg, int(secs), iso(end - int(secs)), iso(end), "32", "jhalfs Totalseconds"))
    else:
        stage, name, birth, end = f[1], f[2], int(f[3]), int(f[4])
        m = re.match(r"(\d+)-[a-z]+-(.+)", name)
        step, pkg = (m.group(1), m.group(2)) if m else ("", name)
        start, source = birth, "log birth to last write"
        # the latest driver start (HH:MM UTC) at or before the end, if it is
        # later than the log's birth: the package was built more than once
        best = None
        for hh, mm in starts.get(name, []):
            day = dt.datetime.fromtimestamp(end, utc).replace(hour=hh, minute=mm, second=0, microsecond=0)
            if day.timestamp() > end + 60:
                day -= dt.timedelta(days=1)
            t = day.timestamp()
            if best is None or t > best:
                best = t
        if best is not None and best > birth + 120:
            start, source = best, "last driver start (minute) to last write; retried"
        jobs = "12" if pkg == "webkitgtk" else "32"
        rows.append(("blfs", stage, step, pkg, max(0, int(end - start)), iso(start), iso(end), jobs, source))
with open(dest, "w") as fh:
    fh.write("track\tstage\tstep\tpackage\tseconds\tstart_utc\tend_utc\tjobs\tsource\n")
    for r in rows:
        fh.write("\t".join(map(str, r)) + "\n")
tot = {}
for r in rows:
    tot[(r[0], r[1])] = tot.get((r[0], r[1]), 0) + r[4]
for k, v in sorted(tot.items()):
    print(f"{k[0]:5} stage {k[1]:4} {v/3600:6.2f} h")
print("top 15:")
for r in sorted(rows, key=lambda r: -r[4])[:15]:
    print(f"  {r[4]/60:7.1f} min  {r[3]}  ({r[0]} {r[1]}; {r[8]})")
print(f"wrote {dest} ({len(rows)} packages)")
PY
rm -f "$raw"
