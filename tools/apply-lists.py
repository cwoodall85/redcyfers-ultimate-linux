#!/usr/bin/env python3
"""Fold the package lists in lists/ into a copy of the archiso profile.

    apply-lists.py LISTS_DIR PROFILE_DIR

Every *.x86_64 list is appended to the profile's packages.x86_64 (the live
ISO) and written to airootfs/etc/ultimate/archinstall.json as archinstall's
"packages" (every installed system). Runs on the build copy of the profile,
never on the one in git.
"""

import json
import pathlib
import sys


def read_list(path):
    names = []
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            names.append(line)
    return names


def main(lists_dir, profile_dir):
    lists_dir, profile = pathlib.Path(lists_dir), pathlib.Path(profile_dir)
    extra = []
    for path in sorted(lists_dir.glob("*.x86_64")):
        for name in read_list(path):
            if name not in extra:
                extra.append(name)

    live = profile / "packages.x86_64"
    have = set(read_list(live))
    with live.open("a") as fh:
        fh.write("\n# --- added at build time from lists/ ---\n")
        for name in extra:
            if name not in have:
                fh.write(name + "\n")

    conf = profile / "airootfs/etc/ultimate/archinstall.json"
    conf.parent.mkdir(parents=True, exist_ok=True)
    config = {
        # The same desktop the live ISO runs, preselected. Without a profile
        # archinstall installs no desktop at all and the machine boots to a
        # text login. Every choice can still be changed in its menu.
        "profile_config": {
            "gfx_driver": "All open-source",
            "greeter": "sddm",
            "profile": {"main": "Desktop", "details": ["KDE Plasma"]},
        },
        "audio_config": {"audio": "pipewire"},
        "network_config": {"type": "nm"},
        "packages": extra,
        # archinstall copies the live system's pacman.conf, and with it the
        # [ultimate] entry pointing at /opt/ultimate-repo, which exists only
        # on the ISO: every `pacman -Sy` on the installed system then fails.
        # Drop the entry until the repository is hosted somewhere reachable.
        "custom_commands": [
            "sed -i '/^# Ultimate Linux packages/,/^Server = file:\\/\\/\\/opt\\/ultimate-repo$/d'"
            " /etc/pacman.conf"
        ],
    }
    conf.write_text(json.dumps(config, indent=2) + "\n")
    print(f"lists: {len(extra)} packages -> packages.x86_64 and {conf.relative_to(profile)}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
