"""ultimate-assistant-mcp -- the Claude bar's assistant mode: tools that act.

The bar's default mode is read-only (sysinfo.py). Assistant mode, switched
on in the bar, gives Claude Code its own tools (shell, files, SSH to your
machines) plus these, which do things on the desktop for you: open
programs, Ultimate SSH sessions, notes, reminders, notifications, the
calendar, volume, the clipboard, and telling you when something finishes.

Which of them run without asking is decided by engine_assist.py
(AUTO_ALLOW); everything else, and every change Claude Code's own tools
would make, comes to the bar as an Allow / Deny question through
approve() below. Nothing here reads or stores credentials.
"""

import configparser
import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime

from . import bar

SERVER = "ultimate-assistant"
INSTRUCTIONS = ("Desktop actions for the user of this Ultimate Linux machine: open "
                "programs, files and web pages; Ultimate SSH sessions; notes; "
                "reminders and notifications; the calendar; volume; the clipboard; "
                "Ultimate Browser tabs (open, navigate, click, fill). "
                "approve is the permission prompt, not a tool to call yourself.")
NOTES = os.path.expanduser("~/Notes")
APPROVAL_TIMEOUT = 15 * 60


def _run(argv, timeout=30, check=True):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError((p.stderr or p.stdout).strip() or f"{argv[0]} failed ({p.returncode})")
    return p.stdout


def _spawn(argv):
    """Start a program detached from us (it outlives this server)."""
    subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


# --- programs, files, web pages ---------------------------------------------------------

def _desktop_files():
    dirs = os.environ.get("XDG_DATA_DIRS", "/usr/share:/opt/kf6/share").split(":")
    dirs = [os.path.expanduser("~/.local/share"),
            os.path.expanduser("~/.local/share/flatpak/exports/share"),
            "/var/lib/flatpak/exports/share"] + dirs
    seen = {}
    for d in dirs:
        for path in glob.glob(os.path.join(d, "applications", "**", "*.desktop"), recursive=True):
            seen.setdefault(os.path.basename(path), path)
    return seen


def _app_entry(path):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        cp.read(path, encoding="utf-8")
        e = cp["Desktop Entry"]
    except (configparser.Error, KeyError, UnicodeDecodeError):
        return None
    if e.get("NoDisplay", "false").lower() == "true" or e.get("Type", "Application") != "Application":
        return None
    return {"name": e.get("Name", ""), "generic": e.get("GenericName", ""),
            "keywords": e.get("Keywords", ""), "comment": e.get("Comment", "")}


def _find_app(name):
    want = name.lower().replace(" ", "")
    best = None
    for fname, path in _desktop_files().items():
        e = _app_entry(path)
        if e is None:
            continue
        n = e["name"].lower().replace(" ", "")
        stem = fname[:-8].lower()
        score = (3 if want in (n, stem) or stem.endswith("." + want) else
                 2 if want in n or want in stem else
                 1 if want in (e["generic"] + e["keywords"]).lower().replace(" ", "") else 0)
        if score and (best is None or score > best[0]):
            best = (score, fname, e["name"])
    return best


def list_apps(query: str = "") -> str:
    """The programs installed on this machine (their menu names), for open_app.

    Args:
        query: only programs whose name, description or keywords contain this
    """
    q = query.lower()
    out = []
    for fname, path in sorted(_desktop_files().items()):
        e = _app_entry(path)
        if e and (not q or q in " ".join(e.values()).lower()):
            out.append(f"{e['name']}  ({fname[:-8]})  {e['generic'] or e['comment']}".rstrip())
    return "\n".join(out[:200]) or "no matching programs"


def open_app(name: str) -> str:
    """Open a program by its name as the menu shows it ("Ultimate Mail",
    "Firefox", "Slack", "System Settings"), or its desktop id.

    Args:
        name: the program's name
    """
    hit = _find_app(name)
    if hit is None:
        return f"No program called {name!r}. list_apps shows what is installed."
    _spawn(["gtk-launch", hit[1]])
    return f"Opened {hit[2]}."


def open_target(target: str) -> str:
    """Open a web page, a file or a folder with its usual program.

    Args:
        target: a URL (https://...) or a path (~ is your home)
    """
    t = os.path.expanduser(target)
    if not re.match(r"^[a-z][a-z0-9+.-]*:", t) and not os.path.exists(t):
        return f"{target} does not exist."
    _spawn(["xdg-open", t])
    return f"Opened {target}."


# --- Ultimate SSH -----------------------------------------------------------------------

def ssh_hosts() -> str:
    """The machines in Ultimate SSH: alias, address and group, one per line.
    Use an alias with ssh_open, or with ssh in the shell."""
    if not shutil.which("ultimate-ssh"):
        return "Ultimate SSH is not installed."
    return _run(["ultimate-ssh", "--list-hosts"]).strip() or "no hosts"


def ssh_open(host: str) -> str:
    """Show the user an Ultimate SSH session on a host (opens a tab, or
    focuses the one that is open). For running something there and seeing
    its output yourself, use ssh in the shell instead.

    Args:
        host: the host's alias in Ultimate SSH (ssh_hosts)
    """
    _spawn(["ultimate-ssh", "--host", host])
    return f"Ultimate SSH: opening {host}."


def ssh_open_command(host: str, command: str) -> str:
    """Open a new Ultimate SSH tab on a host running a command, so the user
    watches it (a long job, an interactive program, Claude Code there).

    Args:
        host: the host's alias in Ultimate SSH
        command: the command line to run on the host
    """
    _spawn(["ultimate-ssh", "--host", host, "--command", command])
    return f"Ultimate SSH: running {command!r} on {host} in a new tab."


# --- notifications, reminders, background work ------------------------------------------

def _say_argv(text):
    return ["ultimate-say", text] if shutil.which("ultimate-say") else None


def notify(title: str, message: str = "", speak: bool = False) -> str:
    """Show a desktop notification now.

    Args:
        title: the headline
        message: the details
        speak: also say it aloud (when a voice is installed)
    """
    _run(["notify-send", "--app-name=Claude", "--icon=dialog-information", title, message])
    if speak and _say_argv(f"{title}. {message}"):
        _spawn(_say_argv(f"{title}. {message}"))
    return "Notified."


def _when_args(when):
    w = when.strip()
    m = re.fullmatch(r"(?:in\s+)?(\d+)\s*(s|sec|secs|seconds?|m|min|mins|minutes?|h|hr|hrs|hours?)", w, re.I)
    if m:
        n, unit = int(m.group(1)), m.group(2)[0].lower()
        return ["--on-active", f"{n}{ {'s': 's', 'm': 'min', 'h': 'h'}[unit]}".replace(" ", "")]
    # a systemd calendar time: "15:00", "2026-10-01 09:30", "Mon 08:00"
    p = subprocess.run(["systemd-analyze", "calendar", w], capture_output=True, text=True)
    if p.returncode != 0:
        raise ValueError(f"can't read the time {when!r}: use '20m', '2h', '15:00' or '2026-10-01 09:30'")
    nxt = re.search(r"Next elapse:\s*(.+)", p.stdout)
    return ["--on-calendar", w], (nxt.group(1).strip() if nxt else w)


def _alert_script(title, message, speak):
    cmd = f"notify-send --app-name=Claude --urgency=critical {shlex.quote(title)} {shlex.quote(message)}"
    if speak and shutil.which("ultimate-say"):
        cmd += f"; ultimate-say {shlex.quote(title + '. ' + message)}"
    return cmd


def remind(when: str, message: str, speak: bool = True) -> str:
    """Remind the user at a time: a notification (and spoken, if a voice is
    installed). Survives the bar closing; not a reboot.

    Args:
        when: '20m', '2h', '90s', '15:00', 'tomorrow 09:00' is not understood -- use '2026-10-01 09:00'
        message: what to remind them of
        speak: also say it aloud
    """
    res = _when_args(when)
    args, shown = (res, when) if isinstance(res, list) else res
    unit = f"ultimate-remind-{uuid.uuid4().hex[:8]}"
    _run(["systemd-run", "--user", "--collect", f"--unit={unit}", "--timer-property=AccuracySec=1s",
          *args, "/bin/sh", "-c", _alert_script("Reminder", message, speak)])
    return f"Reminder set for {shown} ({unit}). reminders lists them; cancel_reminder removes one."


def reminders() -> str:
    """The reminders that are still to come."""
    out = _run(["systemctl", "--user", "list-timers", "--all", "--no-legend", "ultimate-remind-*"], check=False)
    return out.strip() or "no reminders"


def cancel_reminder(unit: str) -> str:
    """Cancel a reminder.

    Args:
        unit: its name from reminders (ultimate-remind-...)
    """
    if not unit.startswith("ultimate-remind-"):
        return "That is not a reminder."
    _run(["systemctl", "--user", "stop", unit + ".timer"], check=False)
    return f"Cancelled {unit}."


def watch_process(pid: int, label: str, speak: bool = True) -> str:
    """Tell the user when a running process finishes (a build, a copy, a
    download): a notification, spoken if a voice is installed.

    Args:
        pid: the process id
        label: what it is, for the message ("the kernel build")
        speak: also say it aloud
    """
    if not os.path.exists(f"/proc/{pid}"):
        return f"No process {pid} is running."
    unit = f"ultimate-watch-{pid}"
    _run(["systemd-run", "--user", "--collect", f"--unit={unit}", "/bin/sh", "-c",
          f"tail --pid={pid} -f /dev/null; " + _alert_script("Finished", f"{label} is done.", speak)])
    return f"Watching {label} (pid {pid}); you'll be told when it ends."


def run_and_tell(command: str, label: str, speak: bool = True) -> str:
    """Run a command in the background, then tell the user it finished and
    whether it worked. Output goes to ~/.cache/ultimate/jobs/<label>.log.

    Args:
        command: the shell command line
        label: a short name for it ("backup", "podman build")
        speak: also say it aloud
    """
    logs = os.path.expanduser("~/.cache/ultimate/jobs")
    os.makedirs(logs, exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-") or "job"
    log = os.path.join(logs, f"{slug}.log")
    unit = f"ultimate-job-{slug}-{uuid.uuid4().hex[:4]}"
    ok = _alert_script("Finished", f"{label} worked.", speak)
    bad = _alert_script("Failed", f"{label} failed; see {log}.", speak)
    _run(["systemd-run", "--user", "--collect", f"--unit={unit}", f"--working-directory={os.path.expanduser('~')}",
          "/bin/bash", "-c", f"( {command} ) > {shlex.quote(log)} 2>&1 && {{ {ok}; }} || {{ {bad}; }}"])
    return f"Started {label} ({unit}); log {log}. You'll be told when it ends."


# --- notes ------------------------------------------------------------------------------

def _note_path(title):
    slug = re.sub(r"[^\w-]+", "-", title.strip().lower()).strip("-")[:80] or "note"
    return os.path.join(NOTES, slug + ".md")


def note_add(text: str, title: str = "") -> str:
    """Write a note in ~/Notes (Markdown). With a title, it adds to that
    note (making it if new); without one, it adds to today's inbox note.

    Args:
        text: what to write down
        title: the note's name ("groceries", "redcyfer ideas")
    """
    os.makedirs(NOTES, exist_ok=True)
    path = _note_path(title) if title else os.path.join(NOTES, f"inbox-{datetime.now():%Y-%m-%d}.md")
    new = not os.path.exists(path)
    with open(path, "a", encoding="utf-8") as fh:
        if new:
            fh.write(f"# {title or 'Inbox ' + f'{datetime.now():%Y-%m-%d}'}\n\n")
        fh.write(f"- {datetime.now():%H:%M}  {text.strip()}\n")
    return f"Noted in {path.replace(os.path.expanduser('~'), '~')}."


def notes(query: str = "") -> str:
    """The notes in ~/Notes, newest first; with a query, the lines that
    match it in any note.

    Args:
        query: words to look for
    """
    files = sorted(glob.glob(os.path.join(NOTES, "*.md")), key=os.path.getmtime, reverse=True)
    if not files:
        return "no notes yet"
    if not query:
        return "\n".join(f"{os.path.basename(f)[:-3]}  ({datetime.fromtimestamp(os.path.getmtime(f)):%Y-%m-%d %H:%M})"
                         for f in files[:100])
    q, hits = query.lower(), []
    for f in files:
        with open(f, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                if q in line.lower():
                    hits.append(f"{os.path.basename(f)[:-3]}:{n}: {line.rstrip()}")
    return "\n".join(hits[:200]) or f"nothing about {query!r}"


def note_read(title: str) -> str:
    """Read one note.

    Args:
        title: its name, as notes lists it
    """
    for path in (os.path.join(NOTES, title + ".md"), _note_path(title)):
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                return fh.read()[:20000]
    return f"No note called {title!r}."


# --- calendar (Ultimate Mail's) ---------------------------------------------------------

def _um(args, timeout=90):
    if not shutil.which("ultimate-mail"):
        raise RuntimeError("Ultimate Mail is not installed")
    return _run(["ultimate-mail", *args], timeout=timeout).strip()


def calendar_agenda(days: int = 7, date: str = "") -> str:
    """The user's calendar: events from a day onward (all calendars that
    Ultimate Mail mirrors, with event ids for calendar_delete).

    Args:
        days: how many days to show
        date: the first day, YYYY-MM-DD (default today)
    """
    args = ["calendar", "--days", str(days)]
    if date:
        args += ["--date", date]
    return _um(args) or "nothing on the calendar"


def calendar_add(title: str, date: str, time: str = "", duration_minutes: int = 60,
                 calendar: str = "", location: str = "", notes: str = "") -> str:
    """Add an event to the user's calendar (through Ultimate Mail; it syncs
    to the account's server).

    Args:
        title: the event's title
        date: YYYY-MM-DD
        time: HH:MM, 24-hour, local time; empty for an all-day event
        duration_minutes: how long it lasts
        calendar: which calendar (a name or id from calendar_list); default the first writable one
        location: where
        notes: details
    """
    args = ["calendar", "add", title, "--on", date]
    if time:
        args += ["--at", time, "--for", str(duration_minutes)]
    else:
        args += ["--all-day"]
    for flag, val in (("--calendar", calendar), ("--location", location), ("--notes", notes)):
        if val:
            args += [flag, val]
    return _um(args) or "added"


def calendar_delete(event_id: str) -> str:
    """Delete an event from the user's calendar.

    Args:
        event_id: the id calendar_agenda shows
    """
    return _um(["calendar", "delete", event_id]) or "deleted"


def calendar_list() -> str:
    """The calendars Ultimate Mail knows, and which ones can be written."""
    return _um(["calendar", "list"])


# --- sound, clipboard -------------------------------------------------------------------

def volume(level: str) -> str:
    """Set or read the speaker volume.

    Args:
        level: '40%', '+10%', '-10%', 'mute', 'unmute', or 'get'
    """
    sink = "@DEFAULT_AUDIO_SINK@"
    if level == "get":
        return _run(["wpctl", "get-volume", sink]).strip()
    if level in ("mute", "unmute"):
        _run(["wpctl", "set-mute", sink, "1" if level == "mute" else "0"])
    else:
        m = re.fullmatch(r"([+-]?)(\d{1,3})%", level.strip())
        if not m:
            return "Say '40%', '+10%', '-10%', 'mute', 'unmute' or 'get'."
        _run(["wpctl", "set-volume", "-l", "1.0", sink, f"{m.group(2)}%{m.group(1)}" if m.group(1) else f"{m.group(2)}%"])
    return _run(["wpctl", "get-volume", sink]).strip()


def clipboard_get() -> str:
    """What is on the clipboard now (text)."""
    return _run(["wl-paste", "--no-newline"], check=False)[:20000] or "the clipboard is empty"


def clipboard_set(text: str) -> str:
    """Put text on the clipboard, ready to paste.

    Args:
        text: the text
    """
    subprocess.run(["wl-copy"], input=text, text=True, timeout=10, check=True)
    return "On the clipboard."


# --- the permission prompt --------------------------------------------------------------

def _summary(tool_name, inp):
    short = tool_name.removeprefix("mcp__").replace("__", ": ")
    if tool_name == "Bash":
        return inp.get("description") or "Run a command", inp.get("command", "")
    if tool_name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return f"{tool_name} a file", inp.get("file_path") or inp.get("notebook_path", "")
    if tool_name.endswith("__browser_click"):
        return f"Click element {inp.get('element')} in browser tab {inp.get('tab')}", ""
    if tool_name.endswith("__browser_fill"):
        return (f"Type into field {inp.get('element')} in browser tab {inp.get('tab')}"
                + (" and submit the form" if inp.get("submit") else ""), str(inp.get("value", ""))[:500])
    if tool_name.endswith("__browser_navigate"):
        return f"Load a new address in browser tab {inp.get('tab')}", str(inp.get("url", ""))
    detail =", ".join(f"{k}={json.dumps(v)[:120]}" for k, v in inp.items())
    return short, detail


def _log_action(where, title, detail, decision):
    d = os.environ.get("ULTIMATE_AGENT_STATE") or os.path.expanduser("~/.local/state/ultimate/agent")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "actions.log"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"at": datetime.now().isoformat(timespec="seconds"), "where": where,
                             "action": title, "detail": detail[:500], "decision": decision}) + "\n")


def _ask_in_chat(thread_id, rid, title, detail):
    """Post the question into the chat thread; the agent service (agentd)
    turns Chris's allow/deny reply into the decision file."""
    from . import agentd, chatapi
    body = (f"⚑ **Before I go on, I need your OK to:** {title}\n\n```\n{detail[:1500]}\n```\n\n"
            "Reply **allow** (this and the rest of this task), **once** (just this step) or **deny**.")
    chatapi.post(body, thread_id=thread_id, attrs={"title": "Claude needs your OK", "notify": "normal"})
    agentd.set_chat_pending(thread_id, rid)


# --- what runs without asking ------------------------------------------------------------
#
# 1. Read-only shell commands: every part of the command line is a command
#    from READ_ONLY (with no writing flags), with no redirect into a file,
#    no command substitution and no sudo.
# 2. The rest of a task once Chris has allowed one of its steps: "allow" in
#    the bar or the chat covers the whole run (this MCP server lives exactly
#    as long as one run), "once" only that step.
# 3. Never without asking, even inside an allowed task: ALWAYS_ASK.

READ_ONLY = {
    "ls", "cat", "head", "tail", "less", "more", "wc", "file", "stat", "du", "df", "free", "uptime",
    "whoami", "id", "hostname", "uname", "date", "pwd", "echo", "printf", "true", "which", "type",
    "command", "whereis", "realpath", "readlink", "basename", "dirname", "tree", "find", "grep",
    "egrep", "fgrep", "rg", "sort", "uniq", "cut", "tr", "column", "jq", "diff", "cmp", "md5sum",
    "sha1sum", "sha256sum", "sha512sum", "ps", "pgrep", "pstree", "top", "lsof", "ss", "netstat",
    "ip", "lsblk", "blkid", "findmnt", "mount", "lspci", "lsusb", "lsmod", "dmesg", "journalctl",
    "systemctl", "pacman", "env", "printenv", "getent", "ldd", "nproc", "lscpu", "sensors", "dig",
    "host", "nslookup", "ping", "tracepath", "fc-list", "fc-match", "xdg-mime", "flatpak", "podman",
    "virsh", "git", "awk", "sed", "test", "[", "timeout",
}
_RO_SUB = {  # commands that are only read-only with these first arguments
    "systemctl": {"status", "is-active", "is-enabled", "is-failed", "list-units", "list-timers",
                  "list-unit-files", "show", "cat", "--user"},
    "pacman": {"-Q", "-Qi", "-Ql", "-Qo", "-Qs", "-Qk", "-Qkk", "-Qq", "-Si", "-Ss", "-Dk"},
    "git": {"status", "log", "diff", "show", "branch", "remote", "rev-parse", "ls-files", "blame"},
    "flatpak": {"list", "info", "search", "remotes"},
    "podman": {"ps", "images", "info", "inspect", "logs", "version", "network", "volume"},
    "virsh": {"list", "dominfo", "domstate", "net-list", "net-dhcp-leases", "domifaddr", "--connect", "-c"},
    "ip": {"addr", "a", "route", "r", "link", "l", "neigh", "-br", "-4", "-6", "-j"},
    "mount": set(),          # bare `mount` lists; any argument could mount
}
_UNSAFE_FLAGS = re.compile(r"(^|\s)(-exec|-execdir|-delete|-ok|-fprint\S*|--in-place|-i\b|-w\b)")
ALWAYS_ASK = re.compile(
    r"(^|[\s;&|(])(sudo|pkexec|su|doas|mkfs\S*|wipefs|shred|sgdisk|sfdisk|parted|fdisk)(\s|$)"
    r"|\bdd\b[^|;&]*\bof=|\brm\s+-[a-z]*r[a-z]*\s+(/|~|\$HOME|/home/\w+)/?(\s|$)"
    r"|\bgit\s+push\b[^|;&]*(--force|-f\b)")


def _segments(cmd):
    # split on ; && || | and newlines, ignoring quoted text roughly
    parts, cur, quote = [], "", None
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if quote:
            cur += c
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
            cur += c
        elif c in ";|\n" or cmd[i:i + 2] == "&&":
            parts.append(cur)
            cur = ""
            if cmd[i:i + 2] in ("&&", "||"):
                i += 1
        else:
            cur += c
        i += 1
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def _read_only(tool_name, inp):
    if tool_name != "Bash":
        return False
    cmd = inp.get("command", "")
    if not cmd or "`" in cmd or "$(" in cmd or ALWAYS_ASK.search(cmd):
        return False
    # redirects into files are writes; 2>/dev/null, >/dev/null and 2>&1 are not
    if re.search(r"(?<![0-9&])>>?(?!\s*/dev/null)(?!&)", re.sub(r"[0-9]?>>?\s*/dev/null|[0-9]>&[0-9]", "", cmd)):
        return False
    for seg in _segments(cmd):
        try:
            words = shlex.split(seg)
        except ValueError:
            return False
        while words and re.match(r"^\w+=", words[0]):     # VAR=value prefix
            words = words[1:]
        if not words:
            continue
        exe = os.path.basename(words[0])
        if exe == "timeout" and len(words) > 2:
            words = words[2:]
            exe = os.path.basename(words[0])
        if exe not in READ_ONLY:
            return False
        if exe in _RO_SUB:
            args = [w for w in words[1:]]
            while exe == "git" and args[:1] == ["-C"] and len(args) > 2:   # git -C DIR status
                args = args[2:]
            if exe == "mount" and args:
                return False
            if exe != "mount" and (not args or not any(a in _RO_SUB[exe] for a in args[:2])):
                return False
            if exe == "systemctl" and any(a in ("start", "stop", "restart", "enable", "disable", "mask",
                                                 "kill", "reload", "daemon-reload", "edit", "set-property")
                                          for a in args):
                return False
        if exe == "sed" and not re.search(r"(^|\s)-n\b", seg):
            return False                                   # sed only as a printer (-n, no -i)
        if _UNSAFE_FLAGS.search(seg) and exe in ("find", "sed"):
            return False
    return True


_task_allowed = False       # this run: Chris allowed the task


def approve(tool_name: str, input: dict, tool_use_id: str = "") -> str:
    """Claude Code's permission prompt (--permission-prompt-tool): shows the
    action to the user where the request came from -- the Claude bar, or the
    chat thread on their phone -- and waits for Allow or Deny.

    Args:
        tool_name: the tool Claude wants to use
        input: its arguments
        tool_use_id: Claude Code's id for the call
    """
    global _task_allowed
    inp = input or {}
    title, detail = _summary(tool_name, inp)
    via = os.environ.get("ULTIMATE_APPROVE_VIA", "bar")
    allow_json = json.dumps({"behavior": "allow", "updatedInput": input})
    risky = tool_name == "Bash" and bool(ALWAYS_ASK.search(inp.get("command", "")))
    if not risky and _read_only(tool_name, inp):
        _log_action(via, title, detail, "allow (read-only)")
        return allow_json
    if _task_allowed and not risky:
        _log_action(via, title, detail, "allow (task already allowed)")
        return allow_json
    rid = uuid.uuid4().hex[:10]
    # "chat:<thread>" asks in chat only; "bar+chat:<thread>" (the bar, mirrored
    # to #claude) asks in both, and whichever answers first decides.
    in_bar = via == "bar" or via.startswith("bar+")
    chat_thread = int(via.split(":", 1)[1]) if ":" in via else None
    if chat_thread:
        try:
            _ask_in_chat(chat_thread, rid, title, detail)
        except Exception as e:
            if not in_bar:                         # can't ask anywhere: don't act
                _log_action(via, title, detail, f"deny (could not ask: {e})")
                return json.dumps({"behavior": "deny", "message": f"Could not ask the user ({e})."})
            chat_thread = None
    if in_bar:
        bar.set_pending({"id": rid, "tool": tool_name, "title": title, "detail": detail[:2000],
                         "asked": time.time(), "risky": risky})
        if bar.speaking():
            try:
                from . import voice
                voice.say(f"I need your OK to {title[0].lower() + title[1:] if title else 'go on'}.")
            except Exception:
                pass
    decision = None
    deadline = time.time() + (30 * 60 if chat_thread else APPROVAL_TIMEOUT)
    try:
        while time.time() < deadline:
            decision = bar.take_decision(rid)
            if decision:
                break
            time.sleep(0.5 if chat_thread else 0.25)
    finally:
        if chat_thread:
            from . import agentd
            agentd.clear_chat_pending(chat_thread, rid)
        if in_bar:
            bar.set_pending(None)
    _log_action(via, title, detail, decision or "timeout")
    if decision == "allow" and not risky:
        _task_allowed = True
    if decision in ("allow", "allow-once"):
        return allow_json
    why = "The user said no." if decision == "deny" else "Nobody answered the permission question."
    return json.dumps({"behavior": "deny", "message": why + " Don't retry it; ask what they want instead."})


# --- schedules (run by the agent service's systemd timers) ------------------------------

def schedule_add(name: str, when: str, prompt: str, allow: str = "") -> str:
    """Create a recurring job: at each time, the assistant runs `prompt` on
    its own and posts the result to #claude (and a notification). Approving
    this call approves the tools in `allow` for every run of it; anything
    else a run wants is asked on the user's phone.

    Args:
        name: short id, letters, digits and dashes ("morning-brief")
        when: a systemd calendar time ("Mon..Fri 08:00", "Sun 03:00", "*-*-* 18:30")
        prompt: what to do each time, written as an instruction
        allow: space-separated tools each run may use without asking, e.g. "Bash(ssh redcyfer *)" or "mcp__ultimate-mail__inbox_digest"
    """
    from . import agentd
    return agentd.schedule_add(name, when, prompt, allow.split() if allow else [])


def schedules() -> str:
    """The recurring jobs, their times and next runs."""
    from . import agentd
    return agentd.schedules_text()


def schedule_remove(name: str) -> str:
    """Delete a recurring job.

    Args:
        name: its name, from schedules
    """
    from . import agentd
    return agentd.schedule_remove(name)


def schedule_run_now(name: str) -> str:
    """Run a recurring job once now, in the background (its result goes to #claude).

    Args:
        name: its name, from schedules
    """
    from . import agentd
    return agentd.schedule_run_now(name)


# --- Ultimate Browser: acting in its tabs (reading is in the browser's own
# read-only tools: browser_tabs, browser_read, browser_elements) ------------

def _browser(cmd, **args):
    from . import browser
    try:
        return browser.text(browser.call(cmd, **args))
    except browser.BrowserError as e:
        return str(e)


def browser_open(url: str, workspace: str = "", background: bool = False) -> str:
    """Open a page in a new tab of Ultimate Browser.

    Args:
        url: the address, or words to search for
        workspace: which workspace (its own logins): e.g. Personal, Work; empty = the current one
        background: open without switching to it
    """
    return _browser("open", url=url, workspace=workspace or None, background=background)


def browser_activate(tab: int) -> str:
    """Bring a tab of Ultimate Browser to the front (and the browser window).

    Args:
        tab: the tab id (from browser_tabs)
    """
    return _browser("activate", tab=tab)


def browser_navigate(tab: int, url: str) -> str:
    """Load a different address in an existing tab of Ultimate Browser.

    Args:
        tab: the tab id (from browser_tabs); -1 for the current tab
        url: the address, or words to search for
    """
    return _browser("navigate", tab=None if tab < 0 else tab, url=url)


def browser_click(tab: int, element: int) -> str:
    """Click a link or button in a tab of Ultimate Browser. Get the element's
    number from browser_elements first (numbers change when the page does).

    Args:
        tab: the tab id; -1 for the current tab
        element: the element number from browser_elements
    """
    return _browser("click", tab=None if tab < 0 else tab, element=element)


def browser_fill(tab: int, element: int, value: str, submit: bool = False) -> str:
    """Type a value into a form field in a tab of Ultimate Browser, as if typed.
    Never use it for passwords or card numbers: ask Chris to type those.

    Args:
        tab: the tab id; -1 for the current tab
        element: the field's number from browser_elements
        value: what to put in the field
        submit: submit the field's form afterwards
    """
    return _browser("fill", tab=None if tab < 0 else tab, element=element, value=value, submit=submit)


TOOLS = [list_apps, open_app, open_target, ssh_hosts, ssh_open, ssh_open_command,
         notify, remind, reminders, cancel_reminder, watch_process, run_and_tell,
         note_add, notes, note_read, calendar_agenda, calendar_add, calendar_delete, calendar_list,
         volume, clipboard_get, clipboard_set, schedule_add, schedules, schedule_remove,
         schedule_run_now, browser_open, browser_activate, browser_navigate, browser_click,
         browser_fill, approve]


def main():
    from . import mcp_server
    tools = {fn.__name__: fn for fn in TOOLS}
    listing = [mcp_server.describe(fn) for fn in TOOLS]
    return mcp_server.main((SERVER, INSTRUCTIONS, listing, tools))


if __name__ == "__main__":
    sys.exit(main())
