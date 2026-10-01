"""Talking to Claude, and Claude talking back -- all on this machine.

    ultimate-listen                 record until you stop talking, print what you said
    ultimate-say TEXT | -           say it aloud (Markdown and code are tidied up first)
    ultimate-say --stop             stop talking
    ultimate-voice                  what is set up: mic, voice, speech model
    ultimate-voice voice NAME       choose the voice (fetched on first use)
    ultimate-voice model NAME       choose the speech model: small.en, large-v3-turbo-q5_0, ...
    ultimate-voice mic NAME         choose the microphone (a PipeWire source name), or "auto"
    ultimate-voice speed N          how slowly to speak: 1.0 normal, 1.15 a little slower, 0.9 faster

Listening is whisper.cpp (whisper-cli), speaking is Piper; both run here,
nothing is sent anywhere. Models and voices live in
~/.local/share/ultimate/voice and are downloaded from Hugging Face the first
time they are used. Settings: ~/.config/ultimate/voice.conf (KEY=value).

The microphone, unless one is set: a Bluetooth headset if one is connected,
else an input called "Mic", else the default input.
"""

import array
import json
import math
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
import wave

DATA = os.path.expanduser("~/.local/share/ultimate/voice")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                    "ultimate", "voice.conf")
DEFAULTS = {"VOICE": "en_US-lessac-medium", "MODEL": "small.en", "MIC": "auto", "SPEED": "1.0"}
WHISPER = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{}.bin"
PIPER = "https://huggingface.co/rhasspy/piper-voices/resolve/main/{lang}/{loc}/{name}/{quality}/{voice}.{ext}"
RATE = 16000


def settings():
    s = dict(DEFAULTS)
    try:
        with open(CONF) as fh:
            for line in fh:
                m = re.match(r"^\s*([A-Z_]+)\s*=\s*(.*?)\s*$", line)
                if m:
                    s[m.group(1)] = m.group(2)
    except OSError:
        pass
    return s


def set_setting(key, value):
    s = settings()
    s[key] = value
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF, "w") as fh:
        fh.write("# Ultimate Linux voice settings (ultimate-voice)\n")
        for k, v in s.items():
            fh.write(f"{k}={v}\n")


def _fetch(url, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".part"
    print(f"downloading {os.path.basename(path)} ...", file=sys.stderr)
    with urllib.request.urlopen(url, timeout=60) as r, open(tmp, "wb") as fh:
        shutil.copyfileobj(r, fh, 1 << 20)
    os.replace(tmp, path)


def model_path(name=None):
    name = name or settings()["MODEL"]
    path = os.path.join(DATA, f"ggml-{name}.bin")
    if not os.path.exists(path):
        _fetch(WHISPER.format(name), path)
    return path


def voice_path(name=None):
    name = name or settings()["VOICE"]
    path = os.path.join(DATA, name + ".onnx")
    if not os.path.exists(path) or not os.path.exists(path + ".json"):
        m = re.match(r"^([a-z]{2})_([A-Z]{2})-(\w+)-(\w+)$", name)
        if not m:
            raise SystemExit(f"not a Piper voice name: {name} (like en_US-lessac-medium)")
        lang, _, speaker, quality = m.groups()
        base = dict(lang=lang, loc=f"{lang}_{m.group(2)}", name=speaker, quality=quality, voice=name)
        _fetch(PIPER.format(ext="onnx", **base), path)
        _fetch(PIPER.format(ext="onnx.json", **base), path + ".json")
    return path


# --- which microphone ----------------------------------------------------------------------

def sources():
    out = subprocess.run(["pactl", "list", "short", "sources"], capture_output=True, text=True).stdout
    return [line.split("\t")[1] for line in out.splitlines()
            if "\t" in line and ".monitor" not in line.split("\t")[1]]


def mic():
    want = settings()["MIC"]
    have = sources()
    if want != "auto" and want in have:
        return want
    for pick in (lambda s: s.startswith("bluez_input"), lambda s: "mic" in s.lower()):
        for s in have:
            if pick(s):
                return s
    return None                     # the default input


# --- listening -----------------------------------------------------------------------------

def _chime(up=True):
    """A short two-note chime: rising when listening starts, falling at the end."""
    if not shutil.which("pw-play"):
        return
    notes = (660, 880) if up else (880, 660)
    samples = array.array("h")
    for f in notes:
        for i in range(int(22050 * 0.07)):
            env = min(1, i / 200) * min(1, (int(22050 * 0.07) - i) / 400)
            samples.append(int(6000 * env * math.sin(2 * math.pi * f * i / 22050)))
    fd, path = tempfile.mkstemp(suffix=".wav")
    with wave.open(os.fdopen(fd, "wb"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
        w.writeframes(samples.tobytes())
    subprocess.Popen(["sh", "-c", f"pw-play {path}; rm -f {path}"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _bt_card(source):
    """The Bluetooth card behind a bluez_input source, and its active profile."""
    mac = source.split(".", 1)[1].split(".")[0].replace(":", "_") if source else ""
    card = f"bluez_card.{mac}"
    out = subprocess.run(["pactl", "list", "cards"], capture_output=True, text=True).stdout
    block = out.split(f"Name: {card}", 1)
    if len(block) < 2:
        return None, None
    m = re.search(r"Active Profile:\s*(\S+)", block[1])
    return card, m.group(1) if m else None


HOLD = 60          # seconds a headset stays in its mic profile after listening
LINK_WAIT = 6      # seconds to wait for a headset's mic to start sending sound


def _hold_path():
    d = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "ultimate")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "voice-headset.json")


class _headset_mode:
    """A Bluetooth headset's mic only exists in its headset (HFP) profile,
    and PipeWire doesn't always switch by itself: switch for the recording.

    The switch is slow (the headset's voice link takes 1.5 s or more, and
    now and then fails) and switching often has crashed WirePlumber, so
    the headset stays in its mic profile for HOLD seconds after listening:
    a follow-up starts at once. A timer then puts back the profile it had
    (usually A2DP, the good-sound one)."""
    # CVSD first: mSBC ("headset-head-unit") needs eSCO, and on an adapter
    # without it the profile switches fine but the mic never sends a sound.
    PROFILES = ("headset-head-unit-cvsd", "headset-head-unit")

    def __init__(self, source):
        self.card, self.now = _bt_card(source) if source and source.startswith("bluez_input") else (None, None)
        self.before = None

    def _switch(self):
        for prof in self.PROFILES:
            if subprocess.run(["pactl", "set-card-profile", self.card, prof],
                              stderr=subprocess.DEVNULL).returncode == 0:
                return True
        return False

    def __enter__(self):
        if not (self.card and self.now):
            return self
        if self.now.startswith("headset"):
            # still held from the last time: put back what it had before that
            try:
                with open(_hold_path()) as fh:
                    held = json.load(fh)
                if held.get("card") == self.card:
                    self.before = held.get("before")
            except (OSError, ValueError):
                pass
        else:
            self.before = self.now
            self._switch()
        return self

    def reset(self):
        """The voice link didn't come up: drop it and set it up again."""
        if self.card:
            subprocess.run(["pactl", "set-card-profile", self.card, self.before or "a2dp-sink"],
                           stderr=subprocess.DEVNULL)
            time.sleep(1)
            self._switch()

    def __exit__(self, *exc):
        if not (self.card and self.before):
            return
        token = os.urandom(6).hex()
        with open(_hold_path(), "w") as fh:
            json.dump({"card": self.card, "before": self.before, "token": token}, fh)
        # a timer unit of its own: this process (often a short-lived unit) may be gone by then
        cmd = [sys.executable, "-m", "ultimate_claude.voice", "_restore", token]
        if shutil.which("systemd-run") and subprocess.run(
                ["systemd-run", "--user", "--quiet", "--collect", f"--on-active={HOLD}",
                 f"--unit=ultimate-voice-restore-{token}", *cmd],
                stdin=subprocess.DEVNULL, capture_output=True).returncode == 0:
            return
        subprocess.run(["pactl", "set-card-profile", self.card, self.before])


def _restore(token):
    """Put a held headset back, unless it was used again since (a newer token)."""
    try:
        with open(_hold_path()) as fh:
            held = json.load(fh)
    except (OSError, ValueError):
        return 0
    if held.get("token") != token:
        return 0
    subprocess.run(["pactl", "set-card-profile", held["card"], held["before"]])
    os.remove(_hold_path())
    return 0


def record(max_seconds=30, wait_seconds=8, silence=1.2, on_level=None):
    src = mic()
    with _headset_mode(src) as hs:
        pcm = _record(src, max_seconds, wait_seconds, silence, on_level)
        if pcm is None and hs.card:
            hs.reset()
            pcm = _record(src, max_seconds, wait_seconds, silence, on_level)
    return pcm or b""


def _record(src, max_seconds, wait_seconds, silence, on_level, ready=None):
    """Record from the mic until the speaker stops. Returns 16 kHz mono
    16-bit PCM bytes, b"" if nobody spoke within wait_seconds, or None if
    the mic never started sending sound (a Bluetooth voice link that
    didn't come up).

    Until real sound arrives nothing counts: a headset's link sends
    nothing, or pure zeros, while it connects. Then the room's own noise
    is measured for 0.2 s, ready() is called (the "talk now" chime), and
    speech is told from silence by loudness against that noise."""
    argv = ["pw-record", "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16"]
    if src:
        argv += ["--target", src]
    proc = subprocess.Popen(argv + ["-"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    fd = proc.stdout.fileno()
    frame = RATE * 30 // 1000 * 2           # 30 ms of s16
    audio, pend = bytearray(), b""
    floor, live, t0, started, quiet = [], None, None, None, 0.0
    t_open = time.time()
    try:
        while True:
            # never block for ever: a dead link sends no bytes at all
            r, _, _ = select.select([fd], [], [], 0.5)
            if r:
                data = os.read(fd, frame)
                if not data:
                    break
                pend += data
            now = time.time()
            if live is None and now - t_open > LINK_WAIT:
                return None
            if len(pend) < frame:
                continue
            chunk, pend = pend[:frame], pend[frame:]
            a = array.array("h", chunk)
            if live is None:
                if not any(a):
                    continue                 # the link is still connecting
                live = now
            rms = math.sqrt(sum(x * x for x in a) / max(1, len(a)))
            if on_level:
                on_level(rms)
            if now - live < 0.2:
                floor.append(rms)
                continue
            if t0 is None:
                t0 = now
                if ready:
                    ready()
            audio += chunk
            elapsed = now - t0
            if elapsed < 0.2:                # the chime itself, heard through the mic
                continue
            base = max(sum(floor) / max(1, len(floor)), 60)
            loud = rms > max(base * 3.5, 350)
            if started is None:
                if loud:
                    started = elapsed
                elif elapsed > wait_seconds:
                    return b""
            else:
                quiet = 0 if loud else quiet + 0.03
                if quiet >= silence or elapsed > max_seconds:
                    break
    finally:
        proc.terminate()
        proc.wait()
    return bytes(audio)


def transcribe(pcm):
    if not pcm:
        return ""
    fd, path = tempfile.mkstemp(suffix=".wav")
    try:
        with wave.open(os.fdopen(fd, "wb"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
            w.writeframes(pcm)
        threads = str(max(4, (os.cpu_count() or 8) // 2))
        p = subprocess.run(["whisper-cli", "-m", model_path(), "-f", path, "-t", threads,
                            "-l", "en", "-nt", "-np"], capture_output=True, text=True, timeout=120)
        text = " ".join(line.strip() for line in p.stdout.splitlines() if line.strip())
        # whisper's markers for no speech: [BLANK_AUDIO], (silence), [Music] ...
        text = re.sub(r"\[[A-Z_ ]+\]|\((?:silence|music|noise|inaudible)[^)]*\)", "", text, flags=re.I)
        return re.sub(r"\s+", " ", text).strip()
    finally:
        os.remove(path)


def listen():
    """Chime when the mic is really on (not before), record, transcribe."""
    src = mic()
    with _headset_mode(src) as hs:
        pcm = _record(src, 30, 8, 1.2, None, ready=lambda: _chime(True))
        if pcm is None and hs.card:
            hs.reset()
            pcm = _record(src, 30, 8, 1.2, None, ready=lambda: _chime(True))
        if pcm is None:
            raise RuntimeError("the headset's microphone didn't come on; try again")
        _chime(False)
        time.sleep(0.3)
    return transcribe(pcm)


# --- speaking ------------------------------------------------------------------------------

def speakable(md):
    """Markdown as something worth hearing: code blocks mentioned, not read."""
    t = re.sub(r"```.*?```", " (the command is on screen) ", md, flags=re.S)
    t = re.sub(r"`([^`]+)`", r"\1", t)
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)
    t = re.sub(r"https?://\S+", "the link", t)
    t = re.sub(r"^\s{0,3}(#+|[-*+]|\d+\.)\s+", "", t, flags=re.M)
    t = re.sub(r"[*_~>|]", "", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:12000]     # long answers (a story) are read in full; Esc or the speaker button stops it


def _pidfile():
    d = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "ultimate")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "say.pid")


def stop():
    try:
        with open(_pidfile()) as fh:
            os.killpg(int(fh.read().strip()), signal.SIGTERM)
    except (OSError, ValueError):
        pass


def say(text):
    text = speakable(text)
    if not text:
        return
    stop()
    v = voice_path()
    with open(v + ".json") as fh:
        rate = json.load(fh).get("audio", {}).get("sample_rate", 22050)
    piper = shutil.which("piper") or "piper"
    try:   # piper's length scale: >1 speaks more slowly
        speed = min(2.0, max(0.5, float(settings().get("SPEED", "1.0"))))
    except ValueError:
        speed = 1.0
    cmd = (f"{piper} -m {v} --length-scale {speed} --output-raw 2>/dev/null | "
           f"pw-play --raw --rate {rate} --channels 1 --format s16 -")
    p = subprocess.Popen(["sh", "-c", cmd], stdin=subprocess.PIPE, start_new_session=True)
    with open(_pidfile(), "w") as fh:
        fh.write(str(p.pid))
    p.communicate(text.encode())


# --- commands ------------------------------------------------------------------------------

def main_listen():
    text = listen()
    if not text:
        print("(didn't hear anything)", file=sys.stderr)
        return 1
    print(text)
    return 0


def main_say():
    args = sys.argv[1:]
    if args[:1] == ["--stop"]:
        stop()
        return 0
    text = sys.stdin.read() if args in ([], ["-"]) else " ".join(args)
    say(text)
    return 0


def main():
    args = sys.argv[1:]
    if args[:1] == ["_restore"]:
        return _restore(args[1])
    s = settings()
    if not args:
        print(f"microphone: {mic() or 'the default input'}   (setting: {s['MIC']})")
        print(f"voice:      {s['VOICE']}")
        print(f"speed:      {s['SPEED']}  (1.0 normal, higher is slower)")
        print(f"speech:     whisper {s['MODEL']}")
        print(f"inputs:     {', '.join(sources()) or 'none'}")
        return 0
    key = {"voice": "VOICE", "model": "MODEL", "mic": "MIC", "speed": "SPEED"}.get(args[0])
    if not key or len(args) < 2:
        print(__doc__.strip().split("\n\n")[0], file=sys.stderr)
        return 2
    if key == "SPEED":
        try:
            float(args[1])
        except ValueError:
            print("speed is a number: 1.0 normal, 1.15 a little slower", file=sys.stderr)
            return 2
    set_setting(key, args[1])
    if key == "VOICE":
        voice_path(args[1])
    elif key == "MODEL":
        model_path(args[1])
    print(f"{key.lower()}: {args[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
