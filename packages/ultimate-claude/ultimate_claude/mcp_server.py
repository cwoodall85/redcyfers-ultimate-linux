"""ultimate-mcp -- the system tools as an MCP server, over stdio.

Claude Code (and any other MCP client) gets the same read-only view of the
machine that `ask` has. First login registers it with Claude Code; the
Claude bar passes it to Claude Code directly.

Self-contained on purpose: MCP over stdio is JSON-RPC 2.0, one message per
line, and this server needs four methods (initialize, tools/list,
tools/call, ping). Implementing them here drops the Python MCP SDK and its
dozen dependencies -- which the from-source system doesn't have, and which
changed its API between major versions anyway. Tool schemas come from each
function's signature and its docstring's "Args:" section.
"""

import inspect
import json
import re
import sys

from . import __version__, plugins

SERVER = "ultimate-system"
PROTOCOL = "2025-06-18"
INSTRUCTIONS = ("Read-only inspection of this Ultimate Linux machine: processes, "
                "systemd units and journal, packages, disks, network and hardware. "
                "Nothing here changes the system.")
TYPES = {int: "integer", float: "number", bool: "boolean", str: "string", dict: "object"}


def describe(fn):
    """An MCP tool description built from a function."""
    doc = inspect.getdoc(fn) or ""
    summary, _, argdoc = doc.partition("Args:")
    notes = dict(re.findall(r"^\s*(\w+):\s*(.+)$", argdoc, re.M))
    props, required = {}, []
    for name, p in inspect.signature(fn).parameters.items():
        prop = {"type": TYPES.get(p.annotation, "string")}
        if name in notes:
            prop["description"] = notes[name].strip()
        if p.default is inspect.Parameter.empty:
            required.append(name)
        else:
            prop["default"] = p.default
        props[name] = prop
    return {"name": fn.__name__, "description": " ".join(summary.split()),
            "inputSchema": {"type": "object", "properties": props,
                            "required": required, "additionalProperties": False}}


# The built-in system tools plus any drop-in tool sets (plugins.py).
TOOLS = {fn.__name__: fn for fn in plugins.TOOLS}
LISTING = [describe(fn) for fn in plugins.TOOLS]
if plugins.INSTRUCTIONS:
    INSTRUCTIONS = INSTRUCTIONS + " " + " ".join(plugins.INSTRUCTIONS)


def call(name, arguments, tools=None):
    fn = (TOOLS if tools is None else tools).get(name)
    if fn is None:
        raise KeyError(name)
    params = inspect.signature(fn).parameters
    kwargs = {}
    for key, value in (arguments or {}).items():
        if key not in params:
            raise TypeError(f"unknown argument {key!r}")
        ann = params[key].annotation
        if ann in (int, float) and not isinstance(value, bool):
            value = ann(value)
        elif ann is bool and isinstance(value, str):
            value = value.lower() in ("1", "true", "yes")
        kwargs[key] = value
    return str(fn(**kwargs))


def handle(msg, server=None):
    """The response to one request, or None for a notification.

    server: (name, instructions, listing, tools) for another tool set on
    this same protocol code (the assistant's); default the system tools."""
    name, instructions, listing, tools = server or (SERVER, INSTRUCTIONS, LISTING, TOOLS)
    method, mid, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
    if mid is None:
        return None                                  # notifications need no answer

    def ok(result):
        return {"jsonrpc": "2.0", "id": mid, "result": result}

    def err(code, text):
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": text}}

    if method == "initialize":
        return ok({"protocolVersion": params.get("protocolVersion", PROTOCOL),
                   "capabilities": {"tools": {"listChanged": False}},
                   "serverInfo": {"name": name, "version": __version__},
                   "instructions": instructions})
    if method == "ping":
        return ok({})
    if method == "tools/list":
        return ok({"tools": listing})
    if method == "tools/call":
        try:
            text = call(params.get("name"), params.get("arguments"), tools)
            return ok({"content": [{"type": "text", "text": text}], "isError": False})
        except KeyError:
            return err(-32602, f"unknown tool {params.get('name')!r}")
        except (TypeError, ValueError) as e:
            return err(-32602, str(e))
        except Exception as e:                       # a tool failing is a result
            return ok({"content": [{"type": "text", "text": f"{type(e).__name__}: {e}"}],
                       "isError": True})
    return err(-32601, f"method not found: {method}")


def main(server=None):
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            reply = {"jsonrpc": "2.0", "id": None,
                     "error": {"code": -32700, "message": "parse error"}}
        else:
            reply = handle(msg, server) if isinstance(msg, dict) else None
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
