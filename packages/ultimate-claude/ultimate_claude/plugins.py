"""Extra tool sets for the Claude bar, `ask` and ultimate-mcp.

A package adds tools by dropping a Python file into /usr/lib/ultimate/mcp.d/
(the directory list can be overridden with ULTIMATE_MCP_DIRS, colon-
separated, for testing). Each file is a module with:

    TOOLS = [fn, ...]        functions, described like the built-in ones:
                             typed parameters, a docstring whose first part
                             says what the tool does and whose "Args:" section
                             describes each parameter; each returns text.
    INSTRUCTIONS = "..."     optional: one or two sentences for Claude on
                             when to use these tools.

The contract is the built-in tools' one: **read-only**. A tool may look at
things (files, commands, local HTTP status pages) but never change anything,
and must bound its own time -- `run()` below runs a command with a timeout.
Anything that changes state belongs elsewhere (the RedCyfer home-base
session, for example), not in the Claude bar.

A drop-in that fails to import, or offers a tool whose name is already taken,
is skipped with a warning on stderr; the built-in tools always load.
"""

import importlib.util
import os
import sys

from . import sysinfo

DIRS = os.environ.get("ULTIMATE_MCP_DIRS", "/usr/lib/ultimate/mcp.d").split(":")

# For drop-ins: run a command with a timeout and get its output as text.
run = sysinfo._run


def _load():
    tools = list(sysinfo.TOOLS)
    names = {f.__name__ for f in tools}
    notes = []
    for d in DIRS:
        try:
            files = sorted(f for f in os.listdir(d) if f.endswith(".py") and not f.startswith("_"))
        except OSError:
            continue
        for f in files:
            path = os.path.join(d, f)
            modname = "ultimate_mcp_dropin_" + f[:-3].replace("-", "_")
            try:
                spec = importlib.util.spec_from_file_location(modname, path)
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
            except Exception as e:  # a broken drop-in must not take the bar down
                print(f"ultimate-claude: skipping tool set {path}: {e!r}", file=sys.stderr)
                continue
            for fn in getattr(mod, "TOOLS", []):
                if not callable(fn) or fn.__name__ in names:
                    print(f"ultimate-claude: {path}: skipping tool {getattr(fn, '__name__', fn)!r} "
                          "(not a function, or the name is taken)", file=sys.stderr)
                    continue
                tools.append(fn)
                names.add(fn.__name__)
            if isinstance(getattr(mod, "INSTRUCTIONS", None), str):
                notes.append(mod.INSTRUCTIONS.strip())
    return tools, notes


TOOLS, INSTRUCTIONS = _load()
