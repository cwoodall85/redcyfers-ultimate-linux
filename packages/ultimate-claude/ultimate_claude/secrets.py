"""The assistant's own secrets, in the desktop keyring and nowhere else.

Its own schema, like Ultimate Mail's: it never reads another program's
stored credentials. Today that is one thing, the Ultimate Chat agent token.

    ultimate-agent-token < token      store it (read from stdin, never echoed)
"""

import sys

import gi

gi.require_version("Secret", "1")
from gi.repository import Secret  # noqa: E402

SCHEMA = Secret.Schema.new("dev.ultimatelinux.Assistant", Secret.SchemaFlags.NONE,
                           {"kind": Secret.SchemaAttributeType.STRING})
CHAT_TOKEN = "chat-agent-token"


def store(kind, secret, label):
    if not Secret.password_store_sync(SCHEMA, {"kind": kind}, Secret.COLLECTION_DEFAULT,
                                      label, secret, None):
        raise RuntimeError(f"could not save {kind}")


def lookup(kind):
    return Secret.password_lookup_sync(SCHEMA, {"kind": kind}, None)


def main():
    raw = sys.stdin.read().strip().splitlines()
    token = raw[-1].strip() if raw else ""
    if len(token) < 20 or " " in token:
        print("no token on stdin: nothing stored", file=sys.stderr)
        return 1
    store(CHAT_TOKEN, token, "Ultimate Linux assistant: Ultimate Chat agent token")
    print(f"stored the chat agent token in the keyring ({len(token)} characters)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
