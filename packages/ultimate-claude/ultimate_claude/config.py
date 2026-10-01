"""Where the Claude tools find their model and their key.

The model comes from /etc/ultimate/claude.conf, overridden per user by
~/.config/ultimate/claude.conf. Both are KEY=value files.

The key is never written to a file by these tools. It is read, in order,
from ANTHROPIC_API_KEY, then the desktop keyring (where `ask --login` puts
it), and failing both the SDK's own lookup runs -- which also finds an
`ant auth login` profile.
"""

import os

SYSTEM_CONF = "/etc/ultimate/claude.conf"
USER_CONF = os.path.expanduser("~/.config/ultimate/claude.conf")
KEYRING_SERVICE = "ultimate-claude"
KEYRING_USER = "anthropic-api-key"
DEFAULT_MODEL = "claude-opus-5"


def _read(path):
    values = {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                values[k.strip()] = v.strip().strip('"')
    except OSError:
        pass
    return values


def settings():
    merged = _read(SYSTEM_CONF)
    merged.update(_read(USER_CONF))
    return merged


def model():
    return settings().get("CLAUDE_MODEL") or DEFAULT_MODEL


def api_key():
    """The key to use, or None to let the SDK look for one itself."""
    if os.environ.get("ANTHROPIC_API_KEY"):
        return os.environ["ANTHROPIC_API_KEY"]
    try:
        import keyring
        return keyring.get_password(KEYRING_SERVICE, KEYRING_USER)
    except Exception:
        return None


def store_api_key(key):
    import keyring
    keyring.set_password(KEYRING_SERVICE, KEYRING_USER, key)


def forget_api_key():
    import keyring
    try:
        keyring.delete_password(KEYRING_SERVICE, KEYRING_USER)
    except keyring.errors.PasswordDeleteError:
        pass
