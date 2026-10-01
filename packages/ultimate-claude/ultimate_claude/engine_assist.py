"""The Claude bar's assistant mode: Claude Code that acts, with you in charge.

Unlike engine_cc (read-only, no built-in tools), this runs Claude Code with
its own tools (shell, files, web, SSH to your machines through the shell),
your own MCP servers (Ultimate Mail, Ultimate Chat, ...), the read-only
system tools, and the desktop actions in assistant.py.

    --permission-mode manual        nothing runs unapproved because of
                                    settings elsewhere (auto mode, say) ...
    --allowedTools AUTO_ALLOW       ... except these, which only look, or
                                    do small things that are easy to undo
    --permission-prompt-tool        everything else is asked in the bar:
                                    Allow / Deny (assistant.approve)
    --resume SESSION                follow-ups continue the conversation;
                                    the bar's X (clear) starts a new one

Claude Code's own read-only commands (ls, cat, grep, ...) never prompt.
"""

import json
import os
import shutil
import subprocess
import tempfile

from .engine_cc import NotSignedIn, _args, binary

SERVER = "ultimate-assistant"
PREFIX = f"mcp__{SERVER}__"

_SAFE_ASSISTANT = ["list_apps", "open_app", "open_target", "ssh_hosts", "ssh_open",
                   "notify", "remind", "reminders", "cancel_reminder", "watch_process",
                   "note_add", "notes", "note_read", "calendar_agenda", "calendar_list",
                   "calendar_add", "volume", "clipboard_get", "clipboard_set",
                   "schedules", "schedule_run_now", "browser_open", "browser_activate"]
# Asked every time: ssh_open_command, run_and_tell, calendar_delete,
# browser_navigate/click/fill (acting in a logged-in page),
# schedule_add/remove, the shell (beyond read-only commands), file edits,
# and anything that sends or changes things in Ultimate Mail or Chat.
# The learning loop is the exception: the assistant keeps its own skills
# and memory without asking (plain files, in git-free places it owns).
AUTO_ALLOW = ([f"{PREFIX}{n}" for n in _SAFE_ASSISTANT] +
              ["mcp__ultimate-system", "Read", "Glob", "Grep", "WebSearch", "WebFetch",
               "TodoWrite"] +
              [f"mcp__ultimate-mail__{n}" for n in
               ("accounts", "inbox_digest", "list_messages", "search", "agenda",
                "calendars", "list_rules")] +
              [f"mcp__ultimate-chat__{n}" for n in ("channels", "read", "search", "thread")] +
              [f"{t}(~/.claude/skills/**)" for t in ("Write", "Edit")] +
              [f"{t}(~/.claude/projects/-home-cwoodall/memory/**)" for t in ("Write", "Edit")])

SYSTEM_PROMPT = """\
You are the personal assistant built into this Ultimate Linux desktop, \
talking with its owner through the Claude bar (Meta+Space). You can act: \
open programs, files and pages; take notes; set reminders; tell them when \
background work finishes; read and change their calendar; control volume \
and the clipboard; read their mail and chat; and work on their other \
machines over SSH (ssh <alias> '<command>' in the shell; ssh_hosts lists \
the aliases). You are the one Claude for all of their machines: do the \
work on a remote host yourself over SSH rather than handing it to another \
assistant.

Anything that changes something is shown to them first and needs their \
Allow. One Allow covers the rest of the task: later steps of the same \
request run without asking (read-only commands never ask). So think the \
task through before the first step that needs approval, and if you then \
have to do something materially different from what they asked or what \
you first showed them, do it only if it plainly serves what they asked, \
and say so in your reply ("I also had to ..."). A few things always ask \
(sudo, wiping disks, force-pushing). If they deny something, don't retry \
-- ask what they want instead. Look \
before you act, prefer the smallest change, and never put secrets in \
commands or notes.

Learn as you go. Keep your memory current the way your memory \
instructions say. When you finish a task that took several steps and is \
likely to come up again (a report, a deploy, a fix on one of their \
machines), write it down as a skill in ~/.claude/skills/<name>/SKILL.md \
(frontmatter name + description saying when to use it; then the steps, \
the hosts and commands that worked, and the traps you hit); when you use \
a skill and find it wrong or incomplete, fix it. For recurring work, offer \
a schedule (schedule_add); its approval covers the tools you list for it.

Lead with the result, keep it short and plain, use fenced blocks only for \
commands or output that matters, no tables."""

WHERE = {
    "bar": "They are at the desktop, talking through the Claude bar; replies \
appear in a panel over the desktop and may be read aloud.",
    "chat": "They are writing from Ultimate Chat (#claude), probably on their \
phone and maybe away from the desk: anything you open on the desktop they \
may not see, so say what you did. Anything that needs their OK is asked in \
this chat thread; they answer allow or deny.",
    "schedule": "This is a scheduled run; nobody is watching. Do the job, then \
give the result as a short report. Anything outside the tools approved for \
this schedule is asked in the #claude chat.",
}


def _mcp_config(approve_via):
    servers = {
        SERVER: {"command": shutil.which("ultimate-assistant-mcp") or "/usr/bin/ultimate-assistant-mcp", "args": [],
                 "env": {"ULTIMATE_APPROVE_VIA": approve_via,
                         **{k: os.environ[k] for k in ("ULTIMATE_CHAT_URL", "ULTIMATE_CHAT_TOKEN",
                                                       "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "ULTIMATE_BAR_DIR",
                                                       "ULTIMATE_AGENT_STATE")
                            if k in os.environ}}},
        "ultimate-system": {"command": shutil.which("ultimate-mcp") or "/usr/bin/ultimate-mcp", "args": []},
    }
    fd, path = tempfile.mkstemp(prefix="ultimate-assistant-", suffix=".json")
    with os.fdopen(fd, "w") as fh:
        json.dump({"mcpServers": servers}, fh)
    return path


def run(question, on_event, session=None, model=None, cwd=None,
        approve_via="bar", where="bar", extra_allow=()):
    """Ask in assistant mode. Returns the session id to resume next time.
    approve_via: "bar", or "chat:<thread id>" to ask for permission there.
    where: "bar" | "chat" | "schedule", for the system prompt.
    extra_allow: tool rules pre-approved for this run (a schedule's).
    Raises NotSignedIn or RuntimeError(message)."""
    cfg = _mcp_config(approve_via)
    cmd = [binary() or "claude", "-p", question,
           "--output-format", "stream-json", "--verbose",
           "--mcp-config", cfg,
           "--permission-mode", "manual",
           "--permission-prompt-tool", f"{PREFIX}approve",
           "--allowedTools", *AUTO_ALLOW, *extra_allow,
           "--append-system-prompt", SYSTEM_PROMPT + "\n\n" + WHERE.get(where, "")]
    if session:
        cmd += ["--resume", session]
    if model:
        cmd += ["--model", model]
    new_session = session
    try:
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
            if ev.get("session_id"):
                new_session = ev["session_id"]
            if kind == "assistant":
                for block in ev.get("message", {}).get("content", []):
                    if block.get("type") == "tool_use":
                        name = block.get("name", "")
                        on_event("tool", {"name": name.removeprefix(PREFIX).removeprefix("mcp__"),
                                          "args": _args(block.get("input"))})
            elif kind == "result":
                result = ev
        err = proc.stderr.read()
        proc.wait()
    finally:
        os.unlink(cfg)

    if result is None:
        text = (err or "").strip()
        if session and "no conversation found" in text.lower():
            return run(question, on_event, None, model, cwd, approve_via, where, extra_allow)
        if "login" in text.lower() or "auth" in text.lower():
            raise NotSignedIn()
        raise RuntimeError(text.splitlines()[-1] if text else
                           f"Claude Code exited with {proc.returncode}")
    answer = (result.get("result") or "").strip()
    if result.get("is_error"):
        low = answer.lower()
        if "login" in low or "log in" in low or "authenticat" in low:
            raise NotSignedIn()
        raise RuntimeError(answer or result.get("subtype", "Claude Code failed"))
    if answer:
        on_event("text", answer)
    on_event("done", {"stop_reason": result.get("subtype", "success"),
                      "denied": len(result.get("permission_denials") or [])})
    return new_session
