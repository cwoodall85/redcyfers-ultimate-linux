"""ultimate-claude-bar -- the backend of the Claude bar.

    ultimate-claude-bar ask -- QUESTION   start Claude on QUESTION, return at once
    ultimate-claude-bar state             print the current run as JSON
    ultimate-claude-bar clear             dismiss the current run
    ultimate-claude-bar history [N]       the last N answered questions as JSON
                                          (~/.local/state/ultimate/claude-history.jsonl)
    ultimate-claude-bar demo              play a scripted run (no API key needed)
    ultimate-claude-bar mode [ask|assistant]   show or switch the mode
    ultimate-claude-bar listen            listen to the mic, then ask what was said
    ultimate-claude-bar speak [on|off]    read answers aloud (voice.py)
    ultimate-claude-bar allow ID | allow-once ID | deny ID
                                          answer the assistant's question: allow
                                          covers the rest of that task too

Two modes. "ask" (the default) is read-only: Claude looks at the machine
and tells you what to run. "assistant" acts for you (engine_assist.py):
anything that changes something first appears in the bar as a question,
answered with allow/deny. Assistant follow-ups continue one conversation
until you clear it.

The top-bar widget calls `ask`; a detached worker runs the shared agent
and writes each step to a state file in the user's runtime directory
($XDG_RUNTIME_DIR/ultimate/claude-bar.json, readable only by the user).
The Cognition wallpaper draws that file over the desktop. Nothing listens
on a socket: other users cannot reach it, and it holds no key.

State file:
    {"id", "prompt", "status": "thinking"|"done"|"error",
     "steps": [{"name", "args"}], "text", "error", "started", "updated"}
`state` adds "mode" and, while the assistant waits for you, "pending":
{"id", "tool", "title", "detail"}.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import time
import uuid

MAX_TEXT = 12000
HISTORY_MAX_BYTES = 4 * 1024 * 1024


def state_dir():
    if os.environ.get("ULTIMATE_BAR_DIR"):          # tests: a bar of their own
        os.makedirs(os.environ["ULTIMATE_BAR_DIR"], mode=0o700, exist_ok=True)
        return os.environ["ULTIMATE_BAR_DIR"]
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    d = os.path.join(base, "ultimate")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def state_path():
    return os.path.join(state_dir(), "claude-bar.json")


def _path(name):
    return os.path.join(state_dir(), name)


def mode():
    try:
        with open(os.path.join(_config_dir(), "claude-bar-mode")) as fh:
            m = fh.read().strip()
    except OSError:
        m = ""
    return m if m in ("ask", "assistant") else "ask"


def _config_dir():
    d = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "ultimate")
    os.makedirs(d, exist_ok=True)
    return d


def speaking():
    try:
        with open(os.path.join(_config_dir(), "claude-bar-speak")) as fh:
            return fh.read().strip() == "on"
    except OSError:
        return False


def set_speaking(on):
    with open(os.path.join(_config_dir(), "claude-bar-speak"), "w") as fh:
        fh.write(("on" if on else "off") + "\n")


def set_mode(m):
    with open(os.path.join(_config_dir(), "claude-bar-mode"), "w") as fh:
        fh.write(m + "\n")


def _json_file(name, obj=None, remove=False):
    path = _path(name)
    if remove:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        return None
    if obj is None:
        try:
            with open(path) as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return None
    with open(path + ".tmp", "w") as fh:
        json.dump(obj, fh)
    os.replace(path + ".tmp", path)
    return obj


def set_pending(question):
    """The assistant's open question (assistant.approve), or None."""
    if question is None:
        _json_file("claude-pending.json", remove=True)
    else:
        _json_file("claude-pending.json", question)


def take_decision(rid):
    """'allow' or 'deny' once the user has answered question rid, else None."""
    d = _json_file(f"claude-decision-{rid}.json")
    if d:
        _json_file(f"claude-decision-{rid}.json", remove=True)
        return d.get("decision")
    return None


def read():
    try:
        with open(state_path()) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def write(state):
    state["updated"] = time.time()
    tmp = state_path() + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(state, fh)
    os.replace(tmp, state_path())   # atomic: the reader never sees half a file


def history_path():
    if os.environ.get("ULTIMATE_BAR_DIR"):
        return os.path.join(state_dir(), "claude-history.jsonl")
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    d = os.path.join(base, "ultimate")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return os.path.join(d, "claude-history.jsonl")


def _archive(state, status=None):
    """Keep a finished (or replaced) run: the panel shows one run at a time,
    and a new question used to take the last answer away before it was read."""
    if not state.get("id") or not (state.get("prompt") or state.get("text") or state.get("error")):
        return
    entry = {"id": state["id"], "prompt": state.get("prompt", ""),
             "text": state.get("text", ""), "error": state.get("error", ""),
             "status": status or state.get("status", ""), "mode": state.get("mode", "ask"),
             "steps": len(state.get("steps") or []),
             "started": state.get("started"), "finished": time.time()}
    path = history_path()
    with open(path, "a") as fh:
        fh.write(json.dumps(entry) + "\n")
    os.chmod(path, 0o600)
    if os.path.getsize(path) > HISTORY_MAX_BYTES:
        with open(path) as fh:
            lines = fh.readlines()
        with open(path + ".tmp", "w") as fh:
            fh.writelines(lines[len(lines) // 2:])
        os.replace(path + ".tmp", path)


def history(n=50):
    try:
        with open(history_path()) as fh:
            lines = fh.readlines()
    except OSError:
        return []
    out = []
    for line in lines[-n:]:
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def _stop_previous():
    old = read()
    pid = old.get("pid")
    if old.get("status") in ("thinking", "listening"):
        _archive(old, "stopped")
    if pid and old.get("status") in ("thinking", "listening"):
        try:
            # the worker leads its own process group (start_new_session):
            # this also stops the claude it runs and that one's tools
            os.killpg(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    set_pending(None)


def _new_state(prompt):
    return {"id": uuid.uuid4().hex[:12], "prompt": prompt[:500],
            "status": "thinking", "steps": [], "text": "", "error": "",
            "started": time.time()}


def _spawn(mode, run_id, prompt):
    argv = [sys.executable, "-m", "ultimate_claude.bar", mode, run_id, prompt]
    # Run as its own transient user unit: a child of plasmashell (which runs
    # `ask` for the widget) is in plasmashell's cgroup, so restarting the
    # panel -- or Plasma crashing -- would kill a run waiting for an answer.
    if shutil.which("systemd-run"):
        env = [f"--setenv={k}={os.environ[k]}" for k in ("XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "PATH", "PYTHONPATH",
                                                         "WAYLAND_DISPLAY", "DISPLAY", "ULTIMATE_BAR_DIR")
               if k in os.environ]
        p = subprocess.run(["systemd-run", "--user", "--quiet", "--collect",
                            f"--unit=ultimate-claude-bar-{run_id}", *env, *argv],
                           stdin=subprocess.DEVNULL, capture_output=True)
        if p.returncode == 0:
            return
    subprocess.Popen(
        argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=open(os.path.join(state_dir(), "claude-bar.log"), "a"),
        start_new_session=True)


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _recorder(state):
    """An agent callback that writes each event into the state file."""
    def on_event(kind, data):
        if read().get("id") != state["id"]:
            sys.exit(0)            # superseded by a newer question, or cleared
        if kind == "tool":
            state["steps"].append(data)
        elif kind == "text":
            state["text"] = (state["text"] + "\n\n" + data).strip()[:MAX_TEXT]
        elif kind == "done":
            state["status"] = "done"
        write(state)
    return on_event


def _chat_thread(state, prompt):
    """Mirror a bar question into #claude so it can be followed (and its
    permission questions answered) from the phone. One chat thread per
    Assistant conversation; each Ask question is a thread of its own.
    Returns the thread id, or None if chat can't be reached -- the bar
    never waits on chat or fails because of it."""
    try:
        from . import chatapi
        conv = (_json_file("claude-conversation.json") or {}) if state.get("mode") == "assistant" else {}
        tid = conv.get("chat_thread")
        label = "Assistant" if state.get("mode") == "assistant" else "Ask"
        if tid:
            chatapi.post(f"🖥 **Chris, at the desktop:**\n\n{prompt}", thread_id=tid,
                         attrs={"notify": "none", "source": "claude-bar"})
        else:
            root = chatapi.post(f"🖥 **Chris, at the desktop** ({label}):\n\n{prompt}",
                                attrs={"title": "Claude bar: " + prompt[:80], "notify": "none",
                                       "source": "claude-bar"})
            tid = root["id"]
            if state.get("mode") == "assistant":
                conv["chat_thread"] = tid
                _json_file("claude-conversation.json", conv)
        state["chat_thread"] = tid
        write(state)
        return tid
    except Exception as e:
        _log(f"chat mirror: {e}")
        return None


def _chat_answer(state):
    tid = state.get("chat_thread")
    if not tid:
        return
    try:
        from . import chatapi
        text = (f"⚠ {state['error']}" if state.get("error") else state.get("text") or "(done, nothing to report)")
        chatapi.post(text[:60000], thread_id=tid, attrs={"notify": "normal", "source": "claude-bar"})
    except Exception as e:
        _log(f"chat mirror: {e}")


def _log(msg):
    try:
        with open(os.path.join(state_dir(), "claude-bar.log"), "a") as fh:
            fh.write(f"{time.strftime('%F %T')} {msg}\n")
    except OSError:
        pass


def _work(run_id, prompt):
    from .agent import AgentError, run
    state = read()
    if state.get("id") != run_id:
        return 0
    state["pid"] = os.getpid()
    write(state)
    _chat_thread(state, prompt)
    try:
        if state.get("mode") == "assistant":
            _assist(state, prompt)
        else:
            run(prompt, _recorder(state),
                extra_system=" Your answer is shown in a panel over the desktop:"
                             " keep it brief, use short paragraphs and fenced"
                             " code blocks, no tables.")
    except AgentError as e:
        state.update(status="error", error=str(e))
        write(state)
    except Exception as e:                       # show it, don't vanish
        state.update(status="error", error=f"{type(e).__name__}: {e}")
        write(state)
    if read().get("id") == state["id"]:
        _archive(state)
        _chat_answer(state)
    if speaking() and read().get("id") == state["id"]:
        st = read()
        from . import voice
        try:
            voice.say(st.get("text") or st.get("error") or "")
        except Exception:
            pass
    return 0


def _listen_work(run_id):
    """Listen, then run what was heard as a question (same run id)."""
    from . import voice
    state = read()
    if state.get("id") != run_id:
        return 0
    state["pid"] = os.getpid()
    write(state)
    try:
        text = voice.listen()
    except Exception as e:
        text, state["error"] = "", f"couldn't listen: {e}"
    if read().get("id") != run_id:
        return 0
    if not text:
        state.update(status="error", error=state.get("error") or "didn't hear anything")
        write(state)
        return 0
    state.update(status="thinking", prompt=text[:500])
    write(state)
    return _work(run_id, text)


def _assist(state, prompt):
    from . import config, engine_assist
    from .agent import NOT_SIGNED_IN, AgentError
    conv = _json_file("claude-conversation.json") or {}
    tid = state.get("chat_thread")
    try:
        sid = engine_assist.run(prompt, _recorder(state), session=conv.get("session"),
                                model=config.settings().get("CLAUDE_CODE_MODEL"),
                                approve_via=f"bar+chat:{tid}" if tid else "bar")
    except engine_assist.NotSignedIn:
        raise AgentError(NOT_SIGNED_IN) from None
    except RuntimeError as e:
        raise AgentError(str(e)) from None
    if sid:
        conv = _json_file("claude-conversation.json") or {}
        conv.update(session=sid, updated=time.time())
        _json_file("claude-conversation.json", conv)
        if tid:                  # a reply from the phone in that thread carries on this conversation
            try:
                from . import agentd
                agentd.link_thread(tid, sid)
            except Exception as e:
                _log(f"link thread: {e}")


def _demo_work(run_id, prompt):
    """A scripted run for trying the bar without an API key."""
    state = read()
    state["pid"] = os.getpid()
    rec = _recorder(state)
    for name, args in [("system_overview", ""),
                       ("top_processes", 'sort_by="cpu", count=10'),
                       ("process_tree", "pid=4127")]:
        time.sleep(1.4)
        rec("tool", {"name": name, "args": args})
    time.sleep(1.2)
    rec("text", "**plasmashell** is using 38% of one core, and it's the Cognition "
                "wallpaper plus seven live monitors redrawing.\n\nThat's expected on a VM "
                "without GPU acceleration. On real hardware it drops to a few percent. "
                "To lower it now, reduce the wallpaper's frame rate:\n\n"
                "```\nRight-click the desktop → Configure Desktop → Frames per second: 12\n```")
    rec("done", {"stop_reason": "end_turn"})
    _archive(state)
    return 0


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print(__doc__.strip().split("\n\n")[0], file=sys.stderr)
        return 2
    cmd = args.pop(0)
    if cmd in ("_work", "_demo"):
        return (_work if cmd == "_work" else _demo_work)(args[0], args[1])
    if cmd == "_listen":
        return _listen_work(args[0])
    if cmd == "listen":
        _stop_previous()
        try:
            from . import voice
            voice.stop()
        except Exception:
            pass
        state = _new_state("")
        state["mode"] = mode()
        state["status"] = "listening"
        write(state)
        _spawn("_listen", state["id"], "")
        return 0
    if cmd == "speak":
        if args:
            set_speaking(args[0] == "on")
            if args[0] != "on":
                try:
                    from . import voice
                    voice.stop()
                except Exception:
                    pass
        print("on" if speaking() else "off")
        return 0
    if cmd == "state":
        st = read()
        # A run whose worker died (killed, crashed, a reboot) would sit at
        # "thinking" for ever, its question unanswerable: say so instead.
        if st.get("status") in ("thinking", "listening") and st.get("pid") and not _alive(st["pid"]):
            st.update(status="error", error="interrupted: ask again")
            write(st)
            set_pending(None)
        st["mode"] = mode()
        st["speak"] = speaking()
        pending = _json_file("claude-pending.json")
        if pending and st.get("status") == "thinking":
            st["pending"] = pending
        print(json.dumps(st))
        return 0
    if cmd == "history":
        n = int(args[0]) if args and args[0].isdigit() else 50
        print(json.dumps(history(n)))
        return 0
    if cmd == "mode":
        if args:
            if args[0] not in ("ask", "assistant"):
                print("mode is ask or assistant", file=sys.stderr)
                return 2
            set_mode(args[0])
        print(mode())
        return 0
    if cmd in ("allow", "allow-once", "deny"):
        if not args:
            print(f"{cmd} which question?", file=sys.stderr)
            return 2
        pending = _json_file("claude-pending.json")
        if not pending or pending.get("id") != args[0]:
            print("no such question open", file=sys.stderr)
            return 1
        _json_file(f"claude-decision-{args[0]}.json", {"decision": cmd})
        return 0
    if cmd == "clear":
        _json_file("claude-conversation.json", remove=True)   # next question starts fresh
        _stop_previous()
        try:
            os.remove(state_path())
        except FileNotFoundError:
            pass
        return 0
    if cmd in ("ask", "demo"):
        if args and args[0] == "--":
            args.pop(0)
        prompt = " ".join(args).strip() or (
            "Why is my CPU busy?" if cmd == "demo" else "")
        if not prompt:
            print("Nothing to ask.", file=sys.stderr)
            return 2
        _stop_previous()
        state = _new_state(prompt)
        state["mode"] = mode() if cmd == "ask" else "ask"
        write(state)
        _spawn("_work" if cmd == "ask" else "_demo", state["id"], prompt)
        return 0
    print(f"unknown command {cmd!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
