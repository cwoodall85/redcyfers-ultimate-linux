#!/usr/bin/env python3
"""Write jhalfs's `configuration` without its interactive menu.

    write-jhalfs-config.py JHALFS_DIR KERNEL_CONFIG

Uses jhalfs's own bundled kconfiglib, so dependent defaults resolve the
same way the menu would resolve them. Every choice below is deliberate;
the rest are jhalfs defaults.
"""
import os
import sys

jhalfs, kernel_config = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(jhalfs, "menu"))
os.environ.setdefault("CONFIG_", "")
os.chdir(jhalfs)
import kconfiglib  # noqa: E402

k = kconfiglib.Kconfig("Config.in", warn=False)
settings = [
    # the book: LFS 13.1, systemd edition, pinned to its release tag
    ("BOOK_LFS_SYSD", "y"), ("BRANCH", "y"), ("COMMIT", "r13.1"),
    ("BUILD_CHROOT", "y"),
    ("BUILDDIR", "/mnt/build_dir"),
    # sources: fetched once into a cache that survives rebuilds
    ("GETPKG", "y"), ("SRC_ARCHIVE", "/sources-cache"),
    ("RETRYSRCDOWNLOAD", "y"), ("RETRYDOWNLOADCNT", "5"), ("DOWNLOADTIMEOUT", "60"),
    ("RUNMAKE", "n"), ("ALL_CORES", "y"),
    # test suites triple the build time; the distro's own CI can run them
    ("CONFIG_TESTS", "n"),
    # every final-system package becomes a pacman package
    ("PKGMNGT", "y"), ("PKG_PACK", "y"),
    ("STRIP", "y"), ("NO_PROGRESS_BAR", "y"), ("REPORT", "y"),
    ("CONFIG_BUILD_KERNEL", "y"), ("CONFIG", kernel_config),
    # system defaults; the network values suit the libvirt default network
    ("TIMEZONE", "UTC"), ("LANG", "en_US.UTF-8"), ("HOSTNAME", "ultimate"),
    ("INTERFACE", "enp1s0"), ("IP_ADDR", "192.168.122.50"),
    ("GATEWAY", "192.168.122.1"), ("PREFIX", "24"),
    ("BROADCAST", "192.168.122.255"), ("DOMAIN", "local"),
    ("DNS1", "192.168.122.1"), ("DNS2", "9.9.9.9"),
]
for name, value in settings:
    sym = k.syms[name]
    if not sym.set_value(value) or sym.str_value != value:
        sys.exit(f"could not set {name}={value} (got {sym.str_value!r}, visibility {sym.visibility})")
k.write_config("configuration")
print("wrote", os.path.join(jhalfs, "configuration"))
