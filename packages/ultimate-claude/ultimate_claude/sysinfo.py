"""Read-only views of the running system.

These functions are the whole surface Claude gets onto the machine, shared
by the `ask` command and the `ultimate-mcp` server. Every one of them only
reads. Nothing here starts, stops, installs, writes or deletes -- a change
to the system is something the user runs, after reading what Claude says.

Each returns plain text, trimmed to a size that is useful to read rather
than everything the command can print.
"""

import os
import shutil
import subprocess

MAX_CHARS = 12000


def _run(argv, timeout=20):
    """Run a command with no shell and return its output, trimmed."""
    if shutil.which(argv[0]) is None:
        return f"{argv[0]} is not installed on this system."
    try:
        out = subprocess.run(argv, capture_output=True, text=True,
                             timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        return f"{' '.join(argv)} timed out after {timeout}s."
    text = (out.stdout or "") + (("\n" + out.stderr) if out.stderr else "")
    text = text.strip() or "(no output)"
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS] + f"\n… trimmed, {len(text) - MAX_CHARS} more characters"
    return text


def _clamp(n, lo, hi):
    try:
        n = int(n)
    except (TypeError, ValueError):
        return lo
    return max(lo, min(hi, n))


def system_overview() -> str:
    """Distro, kernel, uptime, load, memory, and the busiest processes."""
    parts = []
    try:
        with open("/etc/os-release") as fh:
            parts.append(fh.read().strip())
    except OSError:
        pass
    parts.append(_run(["uname", "-srmo"]))
    parts.append(_run(["uptime"]))
    parts.append(_run(["free", "-h"]))
    parts.append(f"CPU cores: {os.cpu_count()}")
    return "\n\n".join(parts)


def top_processes(sort_by: str = "cpu", count: int = 15) -> str:
    """The processes using the most CPU or memory right now.

    Args:
        sort_by: "cpu" or "memory".
        count: How many processes to list, 1 to 50.
    """
    key = "-%mem" if sort_by == "memory" else "-%cpu"
    count = _clamp(count, 1, 50)
    out = _run(["ps", "-eo", "pid,ppid,user,%cpu,%mem,etime,args",
                f"--sort={key}"])
    # Command lines can run to thousands of characters (a VM's QEMU line
    # does); 200 is plenty to identify a process.
    return "\n".join(line[:200] for line in out.splitlines()[:count + 1])


def process_tree(pid: int) -> str:
    """A process, its parents up to PID 1, and its children.

    Args:
        pid: The process id to trace.
    """
    pid = _clamp(pid, 1, 2**22)
    chain = []
    current = pid
    for _ in range(40):
        line = _run(["ps", "-o", "pid=,ppid=,user=,etime=,args=", "-p",
                     str(current)])
        if line == "(no output)":
            break
        chain.append(line)
        try:
            current = int(line.split()[1])
        except (IndexError, ValueError):
            break
        if current <= 1:
            break
    children = _run(["ps", "--ppid", str(pid), "-o", "pid=,%cpu=,args="])
    return ("Parents, nearest first:\n" + "\n".join(chain)
            + "\n\nChildren:\n" + children)


def failed_units() -> str:
    """systemd units that are in a failed state, system and user."""
    return ("System:\n" + _run(["systemctl", "--failed", "--no-legend",
                                "--no-pager"])
            + "\n\nUser:\n" + _run(["systemctl", "--user", "--failed",
                                    "--no-legend", "--no-pager"]))


def service_status(unit: str, user: bool = False) -> str:
    """The status of one systemd unit, with its most recent log lines.

    Args:
        unit: The unit name, for example "sshd.service".
        user: True for a user unit rather than a system one.
    """
    if not unit or unit.startswith("-"):
        return "Give a unit name."
    argv = ["systemctl"] + (["--user"] if user else []) + [
        "status", "--no-pager", "--lines=30", "--", unit]
    return _run(argv)


def journal(unit: str = "", since: str = "1 hour ago", priority: str = "",
            lines: int = 200) -> str:
    """Read the systemd journal.

    Args:
        unit: Limit to one unit, or leave empty for everything.
        since: A journalctl time, such as "1 hour ago" or "today".
        priority: Lowest priority to show, such as "err" or "warning".
        lines: How many of the most recent lines, 1 to 1000.
    """
    argv = ["journalctl", "--no-pager", "-o", "short-iso", "-n",
            str(_clamp(lines, 1, 1000)), "--since", since]
    if unit:
        argv += ["-u", unit]
    if priority:
        argv += ["-p", priority]
    return _run(argv)


def kernel_messages(lines: int = 100) -> str:
    """Recent kernel messages: hardware, drivers, OOM kills.

    Args:
        lines: How many of the most recent lines, 1 to 1000.
    """
    return _run(["journalctl", "-k", "--no-pager", "-o", "short-iso", "-n",
                 str(_clamp(lines, 1, 1000))])


def disk_usage() -> str:
    """Mounted filesystems with their size and free space."""
    return _run(["df", "-hT", "-x", "tmpfs", "-x", "devtmpfs", "-x",
                 "squashfs", "-x", "overlay"])


def package_info(name: str) -> str:
    """Details of an installed package, or of one in the repositories.

    Args:
        name: The package name.
    """
    if not name or name.startswith("-"):
        return "Give a package name."
    out = _run(["pacman", "-Qi", "--", name])
    if "was not found" in out:
        out = "Not installed. From the repositories:\n" + _run(
            ["pacman", "-Si", "--", name])
    return out


def package_search(query: str) -> str:
    """Search the configured repositories for packages.

    Args:
        query: Words to search package names and descriptions for.
    """
    if not query or query.startswith("-"):
        return "Give something to search for."
    return _run(["pacman", "-Ss", "--", query])


def which_package_owns(path: str) -> str:
    """Which installed package a file belongs to.

    Args:
        path: An absolute file path, or a command name.
    """
    if not path or path.startswith("-"):
        return "Give a path."
    if not path.startswith("/"):
        found = shutil.which(path)
        if found is None:
            return f"No command named {path} on the PATH."
        path = found
    return _run(["pacman", "-Qo", "--", path])


def network_overview() -> str:
    """Interfaces, addresses, routes, DNS, and listening sockets."""
    return "\n\n".join([
        _run(["ip", "-brief", "address"]),
        _run(["ip", "route"]),
        _run(["resolvectl", "status", "--no-pager"])
        if shutil.which("resolvectl") else "",
        _run(["ss", "-tulpn"]),
    ]).strip()


def hardware() -> str:
    """CPU, PCI devices with their drivers, and block devices."""
    return "\n\n".join([
        _run(["lscpu"]),
        _run(["lspci", "-k"]),
        _run(["lsblk", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL"]),
    ])


# The order Claude sees them in.
TOOLS = [system_overview, top_processes, process_tree, failed_units,
         service_status, journal, kernel_messages, disk_usage, package_info,
         package_search, which_package_owns, network_overview, hardware]
