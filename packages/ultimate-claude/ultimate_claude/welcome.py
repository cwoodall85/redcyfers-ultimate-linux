"""ultimate-claude-welcome -- sign in to Claude after installing.

Runs from autostart on a user's first desktop login. It exits quietly on
the live ISO, when Claude Code is already signed in, or once it has been
shown. Otherwise it opens a terminal that explains the Claude features and
runs `claude auth login --claudeai`, which signs in to the user's Claude
subscription in their browser. Run it by hand to sign in any time.
"""

import os
import shlex
import shutil
import subprocess
import sys

from . import engine_cc

MARKER = os.path.expanduser("~/.config/ultimate/claude-welcome-done")

BANNER = """\

  Welcome to Ultimate Linux.

  Claude is built into this desktop:
    Meta+Space     ask Claude from the top bar; its work appears on the desktop
    ask <question> the same from any terminal
    claude         Claude Code, with this machine's system tools

  Sign in with your Claude subscription to use them. A browser window opens;
  choose your Claude account. (API keys work too: `ask --api-key`.)
"""


def _mark():
    os.makedirs(os.path.dirname(MARKER), exist_ok=True)
    open(MARKER, "a").close()


def terminal():
    """The part that runs inside the welcome terminal."""
    print(BANNER)
    if engine_cc.signed_in():
        print("  You're already signed in.\n")
    else:
        if not engine_cc.available():
            try:
                answer = input("  Claude Code isn't installed yet. Install it now with\n"
                               "  Anthropic's installer (into ~/.local/bin, keeps itself\n"
                               "  updated)? [Y/n] ").strip().lower()
            except EOFError:
                answer = "n"
            if answer not in ("", "y", "yes") or not engine_cc.install():
                print("\n  Not installed. Run `ultimate-claude-welcome` whenever you like.")
                _mark()
                return _close()
            from . import setup
            setup.main()   # register the system tools with the new install
            print()
        try:
            answer = input("  Sign in now? [Y/n] ").strip().lower()
        except EOFError:
            answer = "n"
        if answer in ("", "y", "yes"):
            subprocess.run([engine_cc.binary(), "auth", "login", "--claudeai"])
            print("\n  Signed in. Press Meta+Space and ask Claude something."
                  if engine_cc.signed_in() else
                  "\n  Not signed in. Run `ultimate-claude-welcome` whenever you like.")
        else:
            print("\n  Skipped. Run `ultimate-claude-welcome` whenever you like.")
    _mark()
    return _close()


def _close():
    try:
        input("\n  Press Enter to close.")
    except EOFError:
        pass
    return 0


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if "--terminal" in args:
        return terminal()
    automatic = "--autostart" in args
    if automatic:
        if os.path.exists("/run/archiso") or os.path.exists(MARKER):
            return 0                  # live session, or already shown
        if engine_cc.signed_in():
            _mark()
            return 0
    if os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"):
        step = [sys.executable, "-m", "ultimate_claude.welcome", "--terminal"]
        # Ultimate SSH is the distro's terminal; Konsole if it isn't there.
        ussh = shutil.which("ultimate-ssh")
        konsole = shutil.which("konsole")
        if ussh:
            argv = [ussh, "--title", "Claude", "--run", shlex.join(step)]
        elif konsole:
            argv = [konsole, "--hide-menubar", "-p", "tabtitle=Claude", "-e", *step]
        else:
            return terminal()
        subprocess.Popen(argv, start_new_session=True)
        return 0
    return terminal()


if __name__ == "__main__":
    sys.exit(main())
