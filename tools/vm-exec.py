#!/usr/bin/env python3
"""Run a shell command inside the test VM through the QEMU guest agent.

    tools/vm-exec.py 'systemctl --failed'
    tools/vm-exec.py --timeout 1800 'long command'

Prints the command's output and exits with its exit code.
"""

import argparse
import base64
import json
import subprocess
import sys
import time


def agent(domain, payload):
    out = subprocess.run(
        ["virsh", "-c", "qemu:///system", "qemu-agent-command", domain,
         json.dumps(payload)], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "guest agent call failed")
    return json.loads(out.stdout)["return"]


def run(domain, command, timeout):
    pid = agent(domain, {"execute": "guest-exec", "arguments": {
        "path": "/bin/bash", "arg": ["-lc", command],
        "capture-output": True}})["pid"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        st = agent(domain, {"execute": "guest-exec-status",
                            "arguments": {"pid": pid}})
        if st["exited"]:
            for key, stream in (("out-data", sys.stdout), ("err-data", sys.stderr)):
                if st.get(key):
                    stream.write(base64.b64decode(st[key]).decode(errors="replace"))
            return st.get("exitcode", 1)
        time.sleep(1)
    print(f"timed out after {timeout}s", file=sys.stderr)
    return 124


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--domain", default="ultimate-test")
    p.add_argument("--timeout", type=int, default=120)
    p.add_argument("command")
    a = p.parse_args()
    try:
        sys.exit(run(a.domain, a.command, a.timeout))
    except RuntimeError as e:
        print(e, file=sys.stderr)
        sys.exit(2)
