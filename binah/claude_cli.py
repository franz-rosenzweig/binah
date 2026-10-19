"""One small wrapper for every Claude call Binah makes.

Runs `claude -p` on the subscription (not --bare, which needs an API key),
with tools, settings, MCP and session history switched off, from an empty
folder, with our own short system prompt instead of the default one.
Requires structured_output and retries once with a stricter nudge, because
the CLI can report success without it.
"""
import json
import os
import subprocess
import tempfile
import time

from . import config

EMPTY = os.path.join(tempfile.gettempdir(), 'binah-claude-empty')
os.makedirs(EMPTY, exist_ok=True)


def default_model():
    return config.model('main')


class ClaudeError(RuntimeError):
    pass


def ask(prompt, schema, system, model=None, timeout=900):
    model = model or default_model()
    cmd = ['claude', '-p', '--output-format', 'json', '--json-schema', json.dumps(schema),
           '--model', model, '--tools', '', '--setting-sources', '', '--strict-mcp-config',
           '--no-session-persistence', '--system-prompt', system]
    last = None
    for attempt in range(2):
        text = prompt if attempt == 0 else (
            prompt + '\n\nIMPORTANT: answer ONLY by filling in the required JSON structure, covering every item.')
        t0 = time.time()
        r = subprocess.run(cmd, input=text, capture_output=True, text=True, cwd=EMPTY, timeout=timeout)
        try:
            out = json.loads(r.stdout)
        except json.JSONDecodeError:
            last = f'bad JSON from CLI (exit {r.returncode}): {r.stdout[:200]} {r.stderr[:200]}'
            continue
        so = out.get('structured_output')
        if so is not None and not out.get('is_error'):
            return so, {'model': model, 'seconds': round(time.time() - t0, 1),
                        'cost_usd': out.get('total_cost_usd'), 'usage': out.get('usage', {})}
        last = f'no structured_output (subtype={out.get("subtype")}, result={str(out.get("result"))[:200]})'
    raise ClaudeError(last)
