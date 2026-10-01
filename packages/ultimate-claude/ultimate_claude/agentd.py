"""ultimate-agent -- the always-on assistant: one Claude for all of it.

    ultimate-agent serve               the service (systemd --user unit): answers
                                       #claude in Ultimate Chat, from anywhere
    ultimate-agent run-schedule NAME   one run of a recurring job (its timer calls this)
    ultimate-agent schedules           list the recurring jobs
    ultimate-agent status              what it is doing

It is the Claude bar's Assistant mode (engine_assist.py) with more ways in:

  * Ultimate Chat. Every message Chris posts in #claude becomes a job
    (the server's agent channel). The service claims it, runs Claude with
    the thread's own conversation (one Claude Code session per thread, so
    follow-ups remember), and posts the answer into the thread. Anything
    that needs his OK is asked in that thread ("⚑ ... allow / deny"); his
    reply is itself a job, which the service turns into the decision
    instead of a new question.
  * Schedules. A recurring job is made with the schedule_add tool, whose
    approval covers the tools it lists; a systemd user timer runs
    `ultimate-agent run-schedule NAME`, which posts the result to #claude
    and shows a notification.
  * Memory and skills are Claude Code's own, shared with every other way
    of talking to it (this same home directory's memory, ~/.claude/skills).

Other channels on the chat server belong to other runners; this service
only takes #claude.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime

from . import bar, chatapi

STATE = os.environ.get("ULTIMATE_AGENT_STATE") or os.path.expanduser("~/.local/state/ultimate/agent")
SCHEDULES = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                         "ultimate", "agent", "schedules")
UNITS = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                     "systemd", "user")
ONCE = re.compile(r"^\s*(once|allow once|just (this|once)|only this|this once)\b[\s.!]*$", re.I)
ALLOW = re.compile(r"^\s*(allow|allowed|yes|y|ok|okay|approve|approved|go|go ahead|do it)\b[\s.!]*$", re.I)
DENY = re.compile(r"^\s*(deny|denied|no|n|nope|stop|don'?t|cancel)\b[\s.!]*$", re.I)
_lock = threading.Lock()


def _state(name):
    os.makedirs(STATE, exist_ok=True)
    return os.path.join(STATE, name)


def _load(name, default):
    try:
        with open(_state(name)) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def _save(name, obj):
    path = _state(name)
    with open(path + ".tmp", "w") as fh:
        json.dump(obj, fh)
    os.replace(path + ".tmp", path)


def log(msg):
    line = f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}"
    print(line, flush=True)


# --- approvals asked in chat (assistant.approve writes, the job loop answers) -----------

def set_chat_pending(thread_id, rid):
    with _lock:
        p = _load("chat-pending.json", {})
        p[str(thread_id)] = {"id": rid, "asked": time.time()}
        _save("chat-pending.json", p)


def clear_chat_pending(thread_id, rid):
    with _lock:
        p = _load("chat-pending.json", {})
        if p.get(str(thread_id), {}).get("id") == rid:
            del p[str(thread_id)]
            _save("chat-pending.json", p)


def _answer_pending(thread_id, text):
    """If a question is open in this thread and the text answers it, record
    the decision (the same decision files the bar uses). True if it did."""
    p = _load("chat-pending.json", {}).get(str(thread_id))
    if not p:
        return False
    decision = ("allow-once" if ONCE.match(text) else "allow" if ALLOW.match(text)
                else "deny" if DENY.match(text) else None)
    if not decision:
        return False
    bar._json_file(f"claude-decision-{p['id']}.json", {"decision": decision})
    return True


# --- answering #claude -------------------------------------------------------------------

def _transcript(th):
    msgs = [th.get("root")] + list(th.get("replies") or [])
    out = []
    for m in msgs:
        if not m or m.get("deleted"):
            continue
        who = "Chris" if m.get("author_kind") == "human" else (m.get("author") or m.get("author_kind"))
        out.append(f"[{who} {str(m.get('created_at', ''))[:16]}]\n{m.get('body', '')[:8000]}")
    return "\n\n".join(out)[-60000:]


def link_thread(thread_id, session_id):
    """The Claude bar mirrors its conversation into a #claude thread: a reply
    there from the phone resumes the same Claude Code session."""
    with _lock:
        sessions = _load("threads.json", {})
        sessions[str(thread_id)] = session_id
        _save("threads.json", sessions)


def _sync_bar_conversation(thread_id, session_id):
    """...and the other way: after a phone reply, the bar's next question
    continues from it rather than from before it."""
    conv = bar._json_file("claude-conversation.json") or {}
    if conv.get("chat_thread") == thread_id and session_id:
        conv.update(session=session_id, updated=time.time())
        bar._json_file("claude-conversation.json", conv)


def _handle(job):
    from . import config, engine_assist
    tid = job["thread_id"]
    sessions = _load("threads.json", {})
    sid = sessions.get(str(tid))
    try:
        # say it's been picked up: from the phone, silence looks like nothing happened
        try:
            chatapi.post("⏳ On it.", thread_id=tid, attrs={"notify": "none"})
        except chatapi.ChatError:
            pass
        latest = chatapi.message(job["message_id"]).get("body", "")
        if sid:
            prompt = latest
        else:
            prompt = ("Chris wrote in Ultimate Chat (#claude). The thread so far, oldest first:\n\n"
                      f"{_transcript(chatapi.thread(tid))}\n\n---\nAnswer his latest message:\n\n{latest}")
        steps = []
        answer = []
        def on_event(kind, data):
            if kind == "tool":
                steps.append(data.get("name", ""))
            elif kind == "text":
                answer.append(data)
        log(f"job {job['id']} thread {tid}: {latest[:80]!r}")
        new_sid = engine_assist.run(prompt, on_event, session=sid,
                                    model=config.settings().get("CLAUDE_CODE_MODEL"),
                                    approve_via=f"chat:{tid}", where="chat")
        if new_sid:
            with _lock:
                sessions = _load("threads.json", {})
                sessions[str(tid)] = new_sid
                _save("threads.json", sessions)
            _sync_bar_conversation(tid, new_sid)
        text = "\n\n".join(answer).strip() or "(done, nothing to report)"
        chatapi.post(text[:60000], thread_id=tid)
        chatapi.done(job["id"], f"answered ({len(steps)} steps)")
        log(f"job {job['id']} done, {len(steps)} steps")
    except Exception as e:
        log(f"job {job['id']} failed: {e}")
        try:
            chatapi.post(f"Sorry, that failed: `{str(e)[:400]}`", thread_id=tid)
            chatapi.fail(job["id"], str(e))
        except Exception:
            pass


def serve():
    log("ultimate-agent up: answering #claude")
    busy = {}                         # thread id -> worker thread
    seen = set()
    while True:
        try:
            jobs = chatapi.queued_jobs(wait=30)
        except chatapi.ChatError as e:
            if "no Ultimate Chat agent token" in str(e):
                log("no #claude token in the keyring yet (ultimate-agent-token < token); checking again in 5 minutes")
                time.sleep(300)
            else:
                log(f"poll: {e}")
                time.sleep(15)
            continue
        mine = [j for j in jobs if j.get("channel") == chatapi.CHANNEL and j["id"] not in seen]
        if jobs and not mine:
            time.sleep(10)            # other agents' jobs: they stay queued for them
            continue
        for job in mine:
            seen.add(job["id"])
            tid = job["thread_id"]
            try:
                text = chatapi.message(job["message_id"]).get("body", "")
            except chatapi.ChatError:
                text = ""
            if _answer_pending(tid, text):
                try:
                    chatapi.claim(job["id"])
                    chatapi.done(job["id"], "answered a permission question")
                except chatapi.ChatError:
                    pass
                log(f"job {job['id']}: permission answer in thread {tid}")
                continue
            # "allow" with nothing waiting (already answered in the bar, or it
            # timed out) is not a new task: starting one would run a second copy
            # of the conversation next to the first (30 Sep).
            if ONCE.match(text) or ALLOW.match(text) or DENY.match(text):
                try:
                    chatapi.claim(job["id"])
                    chatapi.post("Nothing is waiting for your OK in this thread right now "
                                 "(it was already answered, or it timed out). If a run is still "
                                 "going, its result will appear here.",
                                 thread_id=tid, attrs={"notify": "none"})
                    chatapi.done(job["id"], "no open question")
                except chatapi.ChatError:
                    pass
                log(f"job {job['id']}: '{text[:20]}' with no open question in thread {tid}")
                continue
            # The Claude bar is still working in this thread (its mirror): wait for
            # it, then carry on in the same conversation.
            st = bar.read()
            if st.get("chat_thread") == tid and st.get("status") in ("thinking", "listening"):
                seen.discard(job["id"])
                continue
            if tid in busy and busy[tid].is_alive():
                seen.discard(job["id"])   # one run per thread: pick it up when free
                continue
            try:
                chatapi.claim(job["id"])
            except chatapi.ChatError as e:
                log(f"job {job['id']}: not claimed ({e})")
                continue
            t = threading.Thread(target=_handle, args=(job,), daemon=True)
            busy[tid] = t
            t.start()
        if any(j["id"] not in seen for j in jobs if j.get("channel") == chatapi.CHANNEL):
            time.sleep(2)             # a thread was busy: look again soon


# --- schedules -----------------------------------------------------------------------------

NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,40}$")


def _sched_path(name):
    return os.path.join(SCHEDULES, name + ".json")


def schedule_add(name, when, prompt, allow):
    if not NAME.match(name):
        return "Name it with lowercase letters, digits and dashes."
    p = subprocess.run(["systemd-analyze", "calendar", when], capture_output=True, text=True)
    if p.returncode != 0:
        return f"systemd can't read the time {when!r}: use e.g. 'Mon..Fri 08:00' or '*-*-* 18:30'."
    os.makedirs(SCHEDULES, exist_ok=True)
    os.makedirs(UNITS, exist_ok=True)
    job = {"name": name, "when": when, "prompt": prompt, "allow": allow,
           "created": datetime.now().isoformat(timespec="seconds")}
    with open(_sched_path(name), "w") as fh:
        json.dump(job, fh, indent=2)
    exe = shutil.which("ultimate-agent") or "/usr/bin/ultimate-agent"
    with open(os.path.join(UNITS, f"ultimate-agent-{name}.service"), "w") as fh:
        fh.write(f"[Unit]\nDescription=Ultimate assistant schedule: {name}\n\n"
                 f"[Service]\nType=oneshot\nExecStart={exe} run-schedule {name}\n")
    with open(os.path.join(UNITS, f"ultimate-agent-{name}.timer"), "w") as fh:
        fh.write(f"[Unit]\nDescription=Ultimate assistant schedule: {name}\n\n"
                 f"[Timer]\nOnCalendar={when}\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n")
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
    subprocess.run(["systemctl", "--user", "enable", "--now", f"ultimate-agent-{name}.timer"],
                   capture_output=True, check=False)
    nxt = re.search(r"Next elapse:\s*(.+)", p.stdout)
    return f"Scheduled {name}: {when} (next: {nxt.group(1).strip() if nxt else '?'})."


def schedule_remove(name):
    if not os.path.exists(_sched_path(name)):
        return f"No schedule called {name}."
    subprocess.run(["systemctl", "--user", "disable", "--now", f"ultimate-agent-{name}.timer"],
                   capture_output=True, check=False)
    for f in (f"ultimate-agent-{name}.service", f"ultimate-agent-{name}.timer"):
        try:
            os.remove(os.path.join(UNITS, f))
        except FileNotFoundError:
            pass
    os.remove(_sched_path(name))
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
    return f"Removed {name}."


def schedule_run_now(name):
    if not os.path.exists(_sched_path(name)):
        return f"No schedule called {name}."
    subprocess.run(["systemctl", "--user", "start", "--no-block", f"ultimate-agent-{name}.service"], check=False)
    return f"Started {name}; its result will be in #claude."


def schedules_text():
    out = []
    for f in sorted(os.listdir(SCHEDULES)) if os.path.isdir(SCHEDULES) else []:
        if f.endswith(".json"):
            with open(os.path.join(SCHEDULES, f)) as fh:
                j = json.load(fh)
            out.append(f"{j['name']}: {j['when']} -- {j['prompt'][:100]}"
                       + (f"  [pre-approved: {' '.join(j['allow'])}]" if j.get("allow") else ""))
    timers = subprocess.run(["systemctl", "--user", "list-timers", "--no-legend", "ultimate-agent-*"],
                            capture_output=True, text=True).stdout.strip()
    return ("\n".join(out) or "no schedules") + ("\n\n" + timers if timers else "")


def run_schedule(name):
    from . import config, engine_assist
    with open(_sched_path(name)) as fh:
        job = json.load(fh)
    root = chatapi.post(f"⏰ **{name}** ({datetime.now():%a %H:%M})", attrs={"title": f"Schedule: {name}"})
    tid = root["id"]
    answer = []
    try:
        engine_assist.run(job["prompt"], lambda k, d: answer.append(d) if k == "text" else None,
                          model=config.settings().get("CLAUDE_CODE_MODEL"),
                          approve_via=f"chat:{tid}", where="schedule", extra_allow=job.get("allow", []))
        text = "\n\n".join(answer).strip() or "(done, nothing to report)"
    except Exception as e:
        text = f"The scheduled run failed: `{str(e)[:400]}`"
    chatapi.post(text[:60000], thread_id=tid, attrs={"notify": "normal"})
    subprocess.run(["notify-send", "--app-name=Claude", f"Schedule: {name}", text[:300]], check=False)
    return 0


def status():
    p = subprocess.run(["systemctl", "--user", "is-active", "ultimate-agent"], capture_output=True, text=True)
    pend = _load("chat-pending.json", {})
    print(f"service: {p.stdout.strip()}")
    print(f"conversations: {len(_load('threads.json', {}))} chat threads")
    print(f"waiting for your OK in: {', '.join(pend) or 'nothing'}")
    print(schedules_text())
    return 0


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = args.pop(0) if args else "status"
    if cmd == "serve":
        return serve()
    if cmd == "run-schedule" and args:
        return run_schedule(args[0])
    if cmd == "schedules":
        print(schedules_text())
        return 0
    if cmd == "status":
        return status()
    print(__doc__.strip().split("\n\n")[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
