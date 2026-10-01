#!/usr/bin/env python3
"""Pre-fetch every source a BLFS script would download.

    fetch.py SCRIPTS_DIR SOURCES_DIR

The target system has no wget yet. Each generated script downloads only
if the file is missing from its source directory, so fetching here makes
those branches dead code. Checksums are still verified by the scripts.
"""
import concurrent.futures as cf
import os
import re
import subprocess
import sys

scripts, dest = sys.argv[1], sys.argv[2]
urls = {}
for name in sorted(os.listdir(scripts)):
    text = open(os.path.join(scripts, name), errors="replace").read()
    found = (re.findall(r'wget[^"\n]*"([^"]+)"', text)
             + re.findall(r'wget -T \d+ -t \d+ (\S+)', text)
             # side downloads set URL=... first, then `wget $URL`
             + re.findall(r'^\s*URL=(\S+)', text, re.M))
    for url in found:
        url = url.strip('"')
        if url.startswith(("http://", "https://", "ftp://")):
            urls.setdefault(os.path.basename(url), url)

def get(item):
    fname, url = item
    path = os.path.join(dest, fname)
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return None
    # The book points patches at its development directory, where released
    # patches get removed; the 13.1 release directory keeps them.
    tries = [url]
    if "/patches/blfs/svn/" in url:
        tries.append(url.replace("/patches/blfs/svn/", "/patches/blfs/13.1/"))
    # Last resort: the BLFS 13.1 source mirror, filed by first letter. The
    # scripts still check every file's checksum against the book.
    tries.append(f"https://ftp.osuosl.org/pub/blfs/13.1/{fname[0].lower()}/{fname}")
    for u in tries:
        r = subprocess.run(["wget", "-q", "-T", "60", "-t", "4", "-O", path + ".part", u])
        if r.returncode == 0:
            os.replace(path + ".part", path)
            return None
    try:
        os.remove(path + ".part")
    except OSError:
        pass
    return f"{fname}  <- {url}"

with cf.ThreadPoolExecutor(12) as ex:
    failed = [f for f in ex.map(get, urls.items()) if f]
print(f"{len(urls)} files wanted, {len(failed)} failed")
for f in failed:
    print("  missing:", f)
