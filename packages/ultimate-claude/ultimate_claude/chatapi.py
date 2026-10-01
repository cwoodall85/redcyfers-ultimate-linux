"""A small client for Ultimate Chat (chat.redcyfer.com), the assistant's
line to Chris's phone. The wire contract is ultimate-mail's
docs/ultimate-chat-spec.md; the token is the #claude agent token in the
keyring (secrets.py), scopes read:* post:claude jobs:claude.
"""

import json
import os
import urllib.error
import urllib.request

from . import secrets

BASE = os.environ.get("ULTIMATE_CHAT_URL", "https://chat.redcyfer.com")
CHANNEL = "claude"
AGENT = "claude"
AUTHOR = "Claude"


class ChatError(Exception):
    pass


def _token():
    # ULTIMATE_CHAT_TOKEN: for tests against a stand-in server only
    tok = os.environ.get("ULTIMATE_CHAT_TOKEN") or secrets.lookup(secrets.CHAT_TOKEN)
    if not tok:
        raise ChatError("no Ultimate Chat agent token in the keyring")
    return tok


def call(method, path, body=None, timeout=45):
    req = urllib.request.Request(
        BASE + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + _token(), "Content-Type": "application/json",
                 "User-Agent": "ultimate-agent"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        raise ChatError(f"{method} {path}: {e.code} {detail}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise ChatError(f"{method} {path}: {e}") from None


def queued_jobs(wait=30):
    return call("GET", f"/api/v1/jobs?agent={AGENT}&state=queued&wait={wait}",
                timeout=wait + 15).get("jobs", [])


def claim(job_id, worker="ultimate-agent"):
    return call("POST", f"/api/v1/jobs/{job_id}/claim", {"worker": worker})


def done(job_id, result="answered"):
    return call("POST", f"/api/v1/jobs/{job_id}/done", {"result": result[:500]})


def fail(job_id, result):
    return call("POST", f"/api/v1/jobs/{job_id}/fail", {"result": result[:500]})


def thread(message_id):
    return call("GET", f"/api/v1/messages/{message_id}/thread")


def message(message_id):
    return call("GET", f"/api/v1/messages/{message_id}")


def post(body, thread_id=None, thread_key=None, kind="markdown", attrs=None):
    msg = {"kind": kind, "body": body, "author": AUTHOR, "attrs": attrs or {}}
    if thread_id:
        msg["thread_id"] = thread_id
    elif thread_key:
        msg["thread_key"] = thread_key
    return call("POST", f"/api/v1/channels/{CHANNEL}/messages", msg)
