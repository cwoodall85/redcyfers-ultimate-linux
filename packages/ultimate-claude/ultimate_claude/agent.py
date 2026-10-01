"""The Claude loop shared by `ask` and the Claude bar.

Two engines: Claude Code signed in to your Claude subscription (the
default when available; see engine_cc), or the API with a key.

run() asks Claude a question with the read-only system tools and reports
what happens through a callback, so each front end can show it its own
way: the terminal prints it, the bar writes it where the desktop draws it.

Events passed to on_event(kind, data):
    ("tool", {"name": str, "args": str})   Claude is running a tool
    ("text", str)                          answer text from Claude
    ("done", {"stop_reason": str})         finished normally

Failures a user can act on raise AgentError with a message to show.
"""

import json

from . import config, plugins, sysinfo

SYSTEM_PROMPT = """\
You are the assistant built into Ultimate Linux, a distribution for power \
users. You are answering one person on their own machine.

You have read-only tools that inspect this machine. Use them to look at the \
actual state before answering a question about it; do not guess what a \
process, unit or package is when you can check. You cannot change anything. \
When a fix needs a command, give the exact command in a fenced block for \
the user to run, and say what it changes.

The user is technical. Lead with the answer, keep it short, and skip \
explanations of basics they did not ask about."""

NO_KEY = ("No Anthropic API key found. Run `ask --login`, set "
          "ANTHROPIC_API_KEY, or sign in with `ant auth login`.")
NOT_SIGNED_IN = ("Not signed in to Claude. Run `claude auth login` "
                 "(or `ultimate-claude-welcome`) and choose your Claude "
                 "subscription.")


class AgentError(Exception):
    """A failure with a message fit to show the user."""


def _args(inp):
    return ", ".join(f"{k}={json.dumps(v)}" for k, v in (inp or {}).items())


def engine():
    """Which engine to use: CLAUDE_ENGINE in claude.conf, or automatic --
    Claude Code (your subscription) whenever it is installed, unless an
    API key is set in the environment.

    Automatic mode never reads the keyring: on a fresh account that makes
    KDE pop up "create a new wallet" and blocks the run behind the dialog.
    The keyring is only read when the API engine is chosen explicitly."""
    import os
    choice = config.settings().get("CLAUDE_ENGINE", "auto")
    if choice in ("claude-code", "api"):
        return choice
    from . import engine_cc
    if engine_cc.available() and not os.environ.get("ANTHROPIC_API_KEY"):
        return "claude-code"
    return "api"


def run(question, on_event, tools=True, model=None, extra_system=""):
    if engine() == "claude-code":
        from . import engine_cc
        try:
            return engine_cc.run(question, on_event, SYSTEM_PROMPT + extra_system,
                                 model=model or config.settings().get("CLAUDE_CODE_MODEL"))
        except engine_cc.NotSignedIn:
            raise AgentError(NOT_SIGNED_IN) from None
        except RuntimeError as e:
            raise AgentError(str(e)) from None
    return _run_api(question, on_event, tools, model, extra_system)


def _run_api(question, on_event, tools=True, model=None, extra_system=""):
    import anthropic
    from anthropic import beta_tool

    key = config.api_key()
    client = anthropic.Anthropic(api_key=key) if key else anthropic.Anthropic()
    try:
        runner = client.beta.messages.tool_runner(
            model=model or config.model(),
            max_tokens=16000,
            system=SYSTEM_PROMPT + extra_system,
            tools=[beta_tool(f) for f in plugins.TOOLS] if tools else [],
            messages=[{"role": "user", "content": question}],
            # A declined request is retried on Anthropic's recommended
            # fallback model instead of coming back as a bare refusal.
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
        last = None
        for message in runner:
            last = message
            for block in message.content:
                if block.type == "tool_use":
                    on_event("tool", {"name": block.name, "args": _args(block.input)})
                elif block.type == "text" and block.text.strip() \
                        and message.stop_reason != "tool_use":
                    on_event("text", block.text.strip())
        reason = last.stop_reason if last is not None else "end_turn"
        if reason == "refusal":
            raise AgentError("Claude declined to answer this one.")
        on_event("done", {"stop_reason": reason})
    except anthropic.AuthenticationError:
        raise AgentError(NO_KEY) from None
    except TypeError as e:
        # With no credential anywhere, the SDK fails while building the
        # request headers rather than with an API error.
        if "authentication method" not in str(e):
            raise
        raise AgentError(NO_KEY) from None
    except anthropic.RateLimitError:
        raise AgentError("Rate limited by the API; try again in a minute.") from None
    except anthropic.APIConnectionError as e:
        raise AgentError(f"Could not reach the Claude API: {e}") from None
    except anthropic.APIStatusError as e:
        raise AgentError(f"The API returned {e.status_code}: {e.message}") from None
