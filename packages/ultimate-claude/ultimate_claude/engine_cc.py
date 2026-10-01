"""The Claude Code engine: your Claude subscription, through `claude -p`.

Runs Claude Code headless with only the Ultimate system tools:

    --tools ""              no built-in tools at all (no shell, edits, web)
    --strict-mcp-config     no MCP servers but ours ...
    --mcp-config ...        ... which is ultimate-mcp, read-only
    --allowedTools ...      pre-approved, so a headless run never stalls

and turns its stream-json events into the same events agent.run()
reports. Sign-in is Claude Code's own (`claude auth login`); this module
never touches credentials.
"""

import json
import os
import shutil
import subprocess
import tempfile

SERVER = "ultimate-system"
PREFIX = f"mcp__{SERVER}__"


class NotSignedIn(Exception):
    pass


# Claude Code isn't shipped in the image: Anthropic's own installer puts it in
# ~/.local/bin at first login and keeps it updated. That directory may not be
# on the PATH Plasma started with, so look there too.
INSTALLER = "https://claude.ai/install.sh"


def binary():
    """The claude command, or None if Claude Code isn't installed."""
    found = shutil.which("claude")
    if found:
        return found
    local = os.path.expanduser("~/.local/bin/claude")
    return local if os.access(local, os.X_OK) else None


def available():
    return binary() is not None


def install():
    """Install Claude Code with Anthropic's installer. True if it worked."""
    subprocess.run(["bash", "-c", f"curl -fsSL {INSTALLER} | bash"])
    return available()


def signed_in():
    """True if Claude Code has a working sign-in."""
    if not available():
        return False
    try:
        out = subprocess.run([binary(), "auth", "status", "--json"],
                             capture_output=True, text=True, timeout=20)
        return bool(json.loads(out.stdout or "{}").get("loggedIn"))
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False


def _mcp_config():
    server = shutil.which("ultimate-mcp") or "/usr/bin/ultimate-mcp"
    fd, path = tempfile.mkstemp(prefix="ultimate-mcp-", suffix=".json")
    with os.fdopen(fd, "w") as fh:
        json.dump({"mcpServers": {SERVER: {"command": server, "args": []}}}, fh)
    return path


def _args(inp):
    return ", ".join(f"{k}={json.dumps(v)}" for k, v in (inp or {}).items())


def run(question, on_event, system_prompt, model=None, cwd=None):
    """Ask through Claude Code. Raises NotSignedIn or RuntimeError(message)."""
    cfg = _mcp_config()
    cmd = [binary() or "claude", "-p", question,
           "--output-format", "stream-json", "--verbose",
           "--tools", "",
           "--strict-mcp-config", "--mcp-config", cfg,
           "--allowedTools", f"mcp__{SERVER}",
           "--append-system-prompt", system_prompt]
    if model:
        cmd += ["--model", model]
    try:
        # stdin closed: otherwise claude waits 3s for piped input first.
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, cwd=cwd or os.path.expanduser("~"))
        result = None
        for line in proc.stdout:
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            kind = ev.get("type")
            if kind == "assistant":
                for block in ev.get("message", {}).get("content", []):
                    if block.get("type") == "tool_use":
                        name = block.get("name", "")
                        on_event("tool", {"name": name.removeprefix(PREFIX),
                                          "args": _args(block.get("input"))})
            elif kind == "result":
                result = ev
        err = proc.stderr.read()
        proc.wait()
    finally:
        os.unlink(cfg)

    if result is None:
        text = (err or "").strip()
        if "login" in text.lower() or "auth" in text.lower():
            raise NotSignedIn()
        raise RuntimeError(text.splitlines()[-1] if text else
                           f"Claude Code exited with {proc.returncode}")
    answer = (result.get("result") or "").strip()
    if result.get("is_error"):
        low = answer.lower()
        if "login" in low or "log in" in low or "api key" in low or "authenticat" in low:
            raise NotSignedIn()
        raise RuntimeError(answer or result.get("subtype", "Claude Code failed"))
    if answer:
        on_event("text", answer)
    on_event("done", {"stop_reason": result.get("subtype", "success")})
