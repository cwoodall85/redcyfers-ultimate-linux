#!/usr/bin/env python3
"""Generate build steps for the network tools BLFS doesn't carry.

    gen-nettools.py SRCDIR OUTDIR

Each tool: an upstream release tarball, its checksum, and its build
commands. Checksums come from Arch's current package recipes where those
use a release tarball (sha256 or BLAKE2); for the tools Arch builds from a
git tag, or that have no checksum upstream, the sha256 of the tarball as
first downloaded over HTTPS here is recorded (trust on first use), and
downloading again checks against it. Output: one script per tool in
OUTDIR, named to sort after the BLFS stage-2 plan, in dependency order.
"""
import hashlib
import os
import subprocess
import sys

src, out = sys.argv[1], sys.argv[2]

# name, url, (algo, sum) or None to record, build commands
TOOLS = [
 ("libmnl", "https://www.netfilter.org/projects/libmnl/files/libmnl-1.0.5.tar.bz2",
  ("sha256", "274b9b919ef3152bfb3da3a13c950dd60d6e2bcd54230ffeca298d03b40d0525"),
  "./configure --prefix=/usr --disable-static\nmake\nmake install"),
 ("libnftnl", "https://www.netfilter.org/projects/libnftnl/files/libnftnl-1.3.2.tar.xz", None,
  "./configure --prefix=/usr --disable-static\nmake\nmake install"),
 ("nftables", "https://www.netfilter.org/projects/nftables/files/nftables-1.1.7.tar.xz", None,
  "./configure --prefix=/usr --sysconfdir=/etc --disable-debug --disable-man-doc \\\n"
  "            --without-json --with-cli=readline\nmake\nmake install"),
 ("wireguard-tools", "https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-1.0.20260223.tar.xz", None,
  "make -C src\nmake -C src PREFIX=/usr WITH_BASHCOMPLETION=yes WITH_WGQUICK=yes \\\n"
  "     WITH_SYSTEMDUNITS=yes install"),
 ("ethtool", "https://www.kernel.org/pub/software/network/ethtool/ethtool-7.1.tar.xz", None,
  "./configure --prefix=/usr\nmake\nmake install"),
 ("tcpdump", "https://www.tcpdump.org/release/tcpdump-4.99.7.tar.gz",
  ("b2", "15cb61451ba7b0d60255a335d9741857100bf30f90bf7e737cd625e461ce02cb320905006881e5c8d3e4056fae28282ecf29447f0827a961507fca2db14face7"),
  "./configure --prefix=/usr\nmake\nmake install"),
 ("mtr", "https://github.com/traviscross/mtr/archive/v0.96/mtr-0.96.tar.gz",
  ("b2", "c7dff18b6f6e48a648783d719a6cedd14b141fe2013b75031f3ee830e8c4fb9c93639259c860047c8108c21519df30740f7515256ed08552f7697a42e938257b"),
  "./bootstrap.sh\n./configure --prefix=/usr --sbindir=/usr/bin --without-gtk\nmake\nmake install"),
 ("iperf3", "https://github.com/esnet/iperf/archive/refs/tags/3.21/iperf3-3.21.tar.gz",
  ("b2", "7ac39edca583485ef4943850df79ccfd834439a042caa4cc4c2c8a436a4057f8846738c43dcdc92e32a318a4d0f354cc2449677b2cf94286b05556762a118081"),
  "./configure --prefix=/usr --disable-static\nmake\nmake install"),
 ("socat", "http://www.dest-unreach.org/socat/download/socat-1.8.1.3.tar.gz",
  ("sha256", "06602ffd591e98c75b3dc1d66f0f19136cc666b0b2d95caad987d6ab2cb28097"),
  "# OpenSSL 4 made ASN1_STRING opaque: read it through the accessors.\n"
  "sed -i 's|pName->d.iPAddress->data;|ASN1_STRING_get0_data(pName->d.iPAddress);|\n"
  "        s|pName->d.iPAddress->length;|ASN1_STRING_length(pName->d.iPAddress);|' xio-openssl.c\n"
  "./configure --prefix=/usr\nmake\nmake install"),
 ("arp-scan", "https://github.com/royhills/arp-scan/archive/1.10.0/arp-scan-1.10.0.tar.gz",
  ("sha256", "204b13487158b8e46bf6dd207757a52621148fdd1d2467ebd104de17493bab25"),
  "autoreconf -fiv\n./configure --prefix=/usr --sbindir=/usr/bin\nmake\nmake install"),
 ("ngrep", "https://github.com/jpr5/ngrep/archive/refs/tags/v1.49.0/ngrep-1.49.0.tar.gz", None,
  "./configure --prefix=/usr --with-pcap-includes=/usr/include --enable-ipv6 --enable-pcre2\nmake\nmake install"),
 ("iftop", "http://www.ex-parrot.com/~pdw/iftop/download/iftop-1.0pre4.tar.gz", None,
  "# 2014 code: modern GCC defaults to -fno-common and (GCC 15+) to C23, where\n# \"int f()\" means no arguments\n./configure --prefix=/usr --sbindir=/usr/bin CFLAGS='-O2 -fcommon -std=gnu17'\nmake\nmake install"),
 ("nethogs", "https://github.com/raboof/nethogs/archive/v0.8.8/nethogs-0.8.8.tar.gz",
  ("sha256", "111ade20cc545e8dfd7ce4e293bd6b31cd1678a989b6a730bd2fa2acc6254818"),
  "make nethogs\nmake PREFIX=/usr sbin=/usr/bin install"),
 ("nload", "http://www.roland-riegel.de/nload/nload-0.7.4.tar.gz", None,
  "./configure --prefix=/usr CXXFLAGS='-O2 -std=gnu++14'\nmake\nmake install"),
 ("vnstat", "https://humdi.net/vnstat/vnstat-2.13.tar.gz", None,
  "./configure --prefix=/usr --sysconfdir=/etc --sbindir=/usr/bin\nmake\nmake install\n"
  "install -Dm644 examples/systemd/vnstat.service /usr/lib/systemd/system/vnstat.service"),
 ("ipcalc", "https://github.com/kjokjo/ipcalc/archive/refs/tags/0.51/ipcalc-0.51.tar.gz",
  ("sha256", "a4dbfaeb7511b81830793ab9936bae9d7b1b561ad33e29106faaaf97ba1c117e"),
  "install -Dm755 ipcalc /usr/bin/ipcalc"),
 ("sshpass", "https://downloads.sourceforge.net/sshpass/sshpass-1.10.tar.gz",
  ("sha256", "ad1106c203cbb56185ca3bad8c6ccafca3b4064696194da879f81c8d7bdfeeda"),
  "./configure --prefix=/usr\nmake\nmake install"),
]

TEMPLATE = """#!/bin/bash
# {name} -- not in BLFS; built by hand for the Ultimate layer's network tools.
# Source: {url}
# {note}
set -e
wget -T 30 -t 5 "{url}"
FILE={file}
cd /sources
echo "{sum}  $FILE" | {algo}sum -c -
W=/sources/blfs/extra-{name}
rm -rf $W && mkdir -p $W && cd $W
tar --no-same-owner -xf /sources/$FILE
cd "$(ls -d */ | head -1)"
export MAKEFLAGS="-j$(nproc)"

{build}

cd / && rm -rf $W
ldconfig
"""

for i, (name, url, check, build) in enumerate(TOOLS):
    fname = os.path.basename(url)
    path = os.path.join(src, fname)
    if not os.path.exists(path):
        subprocess.run(["curl", "-sfL", "--max-time", "120", "-o", path, url], check=True)
    data = open(path, "rb").read()
    if check:
        algo, want = check
        got = (hashlib.blake2b(data).hexdigest() if algo == "b2" else hashlib.sha256(data).hexdigest())
        if got != want:
            sys.exit(f"{name}: {algo} mismatch for {fname}")
        note = f"Checksum ({algo}) from Arch's package recipe; verified on download."
    else:
        algo, want = "sha256", hashlib.sha256(data).hexdigest()
        note = "Checksum: sha256 of the release as first downloaded over HTTPS (trust on first use)."
    script = TEMPLATE.format(name=name, url=url, note=note, file=fname, sum=want,
                             algo=algo, build=build)
    # The stage-2 tarball wget line is only for fetch.py; the file is fetched
    # outside the chroot and the script checks it. Keep wget from running:
    script = script.replace(f'wget -T 30 -t 5 "{url}"', f'# fetched by fetch.py: wget -T 30 -t 5 "{url}"')
    with open(os.path.join(out, f"{900 + i:04d}-x-{name}"), "w") as fh:
        fh.write(script)
    print(f"{name:16} {fname:40} {algo}")

# nc: nmap (BLFS stage 2) provides ncat, which speaks netcat's options.
with open(os.path.join(out, f"{900 + len(TOOLS):04d}-x-nc"), "w") as fh:
    fh.write("#!/bin/bash\n# `nc`, as nmap's ncat (built in BLFS stage 2).\nset -e\n"
             "[ -x /usr/bin/ncat ] && ln -sfv ncat /usr/bin/nc\n")
