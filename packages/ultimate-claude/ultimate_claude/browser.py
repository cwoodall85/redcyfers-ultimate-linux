"""Claude's line to Ultimate Browser: its control socket
($XDG_RUNTIME_DIR/ultimate/browser.sock), one JSON object per line each way.
Used by the read-only browser tools (the mcp.d drop-in the browser ships)
and by the assistant's acting tools (open, navigate, click, fill), which go
through the usual approval like any other change.
"""

import itertools
import json
import os
import socket

_ids = itertools.count(1)


class BrowserError(Exception):
    pass


def path():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(base, "ultimate", "browser.sock")


def call(cmd, timeout=35, **args):
    req = {"id": next(_ids), "cmd": cmd, **{k: v for k, v in args.items() if v is not None}}
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(path())
            s.sendall((json.dumps(req) + "\n").encode())
            buf = b""
            while not buf.endswith(b"\n"):
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
    except (FileNotFoundError, ConnectionRefusedError):
        raise BrowserError("Ultimate Browser isn't running (open it first, e.g. with open_app).") from None
    except OSError as e:
        raise BrowserError(f"couldn't reach Ultimate Browser: {e}") from None
    try:
        reply = json.loads(buf)
    except ValueError:
        raise BrowserError("Ultimate Browser sent back something that isn't JSON") from None
    if not reply.get("ok"):
        raise BrowserError(reply.get("error") or "the browser said no")
    return reply.get("result")


def text(result):
    return result if isinstance(result, str) else json.dumps(result, ensure_ascii=False, indent=1)
