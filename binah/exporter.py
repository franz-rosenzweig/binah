"""What I write goes into dated Markdown files, so it outlives the app ("file over app").

Optional: set export_dir in settings (for example a folder in an Obsidian vault).
Each day gets one file; each graded answer appends a short section with what I
wrote, the revision, and the reference.
"""
import json
import os
from datetime import date

from . import config, games


def attempt(c, attempt_id):
    d = config.settings().get('export_dir')
    if not d:
        return
    a = c.execute('select * from attempts where id=?', (attempt_id,)).fetchone()
    item = c.execute('select * from items where id=?', (a['item_id'],)).fetchone()
    if not a or not item or a['game'] not in ('gist', 'subtext', 'bloat', 'jam'):
        return
    ans = json.loads(a['answer'] or '{}')
    key = json.loads(item['key'] or '{}')
    src = json.loads(item['source'] or '{}')
    day = a['day'] or date.today().isoformat()
    lines = [f"\n## {games.GAMES[a['game']]['name']}" + (f" · {src['book']}" if src.get('book') else ''), '']
    if a['game'] == 'gist':
        lines += [f"- My gist: {ans.get('gist', '')}", f"- Reference: {key.get('gist', '')}"]
    elif a['game'] == 'subtext':
        lines += [f"- My read: {ans.get('text', '')}", f"- Reference: {key.get('answer', '')}"]
    elif a['game'] == 'bloat':
        lines += [f"- My cut: {ans.get('text', '')}", f"- The author: {key.get('original', '')}"]
    elif a['game'] == 'jam':
        p = json.loads(item['payload'])
        lines += [f"- Topic: {p.get('topic', '')}", f"- What I said: {ans.get('text', '')}"]
    if a['revision']:
        rv = json.loads(a['revision'])
        lines.append(f"- Revised: {rv.get('gist') or rv.get('text', '')}")
    if a['score'] is not None:
        lines.append(f"- Score: {round(100 * a['score'])}%")
    try:
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, f'{day} Binah.md')
        new = not os.path.exists(path)
        with open(path, 'a', encoding='utf-8') as f:
            if new:
                f.write(f'---\ntype: binah-day\ndate: {day}\ntags: [binah, ai-assisted-note]\n---\n\n# Binah, {day}\n')
            f.write('\n'.join(lines) + '\n')
    except OSError:
        pass
