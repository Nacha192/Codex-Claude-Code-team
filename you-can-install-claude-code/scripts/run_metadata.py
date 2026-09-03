"""Keep only fixed diagnostics and a session UUID; never persist raw CLI output."""
import re
import sys

SESSION = re.compile(r"session id: ([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})")
session_seen = False
for raw in sys.stdin.buffer:
    line = raw.decode('utf-8', errors='replace').strip()
    match = SESSION.fullmatch(line)
    if match and not session_seen:
        print('session id: ' + match[1], flush=True)
        session_seen = True
    elif line.startswith('Not inside a trusted directory'):
        print('Not inside a trusted directory', flush=True)
    elif line.startswith(("You've hit your usage limit", 'Error: usage limit')):
        print('Error: usage limit', flush=True)
