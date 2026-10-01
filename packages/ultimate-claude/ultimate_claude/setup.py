"""ultimate-claude-setup -- wire the system tools into Claude Code.

Runs once per user at first login (a global systemd user unit) and can be
run again by hand. Registering is idempotent: an existing registration is
left as it is.
"""

import os
import shutil
import subprocess
import sys

NAME = "ultimate-system"
MARKER = os.path.expanduser("~/.config/ultimate/claude-setup-done")


def main():
    from .engine_cc import binary
    claude = binary()
    if claude is None:
        print("Claude Code is not installed; nothing to register.")
        return 0
    listed = subprocess.run([claude, "mcp", "get", NAME],
                            capture_output=True, text=True)
    if listed.returncode != 0:
        added = subprocess.run(
            [claude, "mcp", "add", "--scope", "user", NAME, "--",
             "/usr/bin/ultimate-mcp"], capture_output=True, text=True)
        if added.returncode != 0:
            print(added.stdout + added.stderr, file=sys.stderr)
            return 1
        print(f"Registered {NAME} with Claude Code.")
    else:
        print(f"{NAME} is already registered with Claude Code.")
    os.makedirs(os.path.dirname(MARKER), exist_ok=True)
    open(MARKER, "a").close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
