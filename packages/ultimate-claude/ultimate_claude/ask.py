"""ask -- put a question about this machine to Claude.

    ask why is my fan loud
    journalctl -b -p err | ask what is going wrong at boot
    ask --no-tools explain what a bind mount is
    ask --login            sign in with your Claude subscription
    ask --api-key          or store an API key in the keyring instead

Claude can look at the running system through read-only tools (processes,
journal, units, packages, disks, network, hardware) and says which it used.
It cannot change anything. Commands it suggests are yours to run.
"""

import argparse
import getpass
import sys

from . import config

# ask prints to a terminal; the shared prompt is in agent.py.
TERMINAL_STYLE = (" Output goes to a terminal: plain text and fenced code "
                  "blocks only, no tables, no headers.")

DIM = "\033[2m" if sys.stderr.isatty() else ""
RESET = "\033[0m" if sys.stderr.isatty() else ""


def _login():
    key = getpass.getpass("Anthropic API key (input hidden): ").strip()
    if not key:
        print("No key entered; nothing stored.", file=sys.stderr)
        return 1
    config.store_api_key(key)
    print("Stored in the keyring. `ask --logout` removes it.")
    return 0


def _question(args):
    words = " ".join(args.question).strip()
    piped = ""
    if not sys.stdin.isatty():
        piped = sys.stdin.read()
        if len(piped) > 200_000:
            print(f"Input is {len(piped)} characters; only the last 200000 "
                  "are sent.", file=sys.stderr)
            piped = piped[-200_000:]
    if not words and not piped:
        return None
    if piped:
        words = (words or "Explain this.") + (
            "\n\nOutput piped in from the terminal:\n```\n" + piped + "\n```")
    return words


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="ask", description="Ask Claude about this machine.")
    parser.add_argument("question", nargs="*")
    parser.add_argument("--no-tools", action="store_true",
                        help="answer without looking at the system")
    parser.add_argument("--model", help=f"model id (default {config.model()})")
    parser.add_argument("--login", action="store_true",
                        help="sign in with your Claude subscription (Claude Code)")
    parser.add_argument("--api-key", action="store_true",
                        help="use an API key instead: store it in the keyring")
    parser.add_argument("--logout", action="store_true",
                        help="remove the stored API key")
    args = parser.parse_args(argv)

    if args.login:
        import shutil
        import subprocess
        from .engine_cc import binary
        if binary():
            return subprocess.run([binary(), "auth", "login", "--claudeai"]).returncode
        print("Claude Code isn't installed. Run `ultimate-claude-welcome` to install it\n"
              "with Anthropic's installer, or use `ask --api-key` instead.", file=sys.stderr)
        return 1
    if args.api_key:
        return _login()
    if args.logout:
        config.forget_api_key()
        print("Removed the stored key.")
        return 0

    question = _question(args)
    if question is None:
        parser.print_usage(sys.stderr)
        return 2

    from .agent import AgentError, run

    def on_event(kind, data):
        if kind == "tool":
            print(f"{DIM}· {data['name']}({data['args']}){RESET}", file=sys.stderr)
        elif kind == "text":
            print(data)
        elif kind == "done" and data["stop_reason"] == "max_tokens":
            print("(answer cut off at the length limit)", file=sys.stderr)

    try:
        run(question, on_event, tools=not args.no_tools, model=args.model,
            extra_system=TERMINAL_STYLE)
    except AgentError as e:
        print(e, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
