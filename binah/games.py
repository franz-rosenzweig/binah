"""The games: what each one shows, how code scores it, and how Claude grades it.

Two lanes, from the research: anything countable is scored by code instantly
(the weak step's position, the author's word, technique-or-fair, word counts,
pauses), and Claude only judges what needs judgment, always against a hidden
key, with my own hand-scored anchor answers when I have them.

Ratings use the FIRST try's score, because they measure unaided skill. The
revision is where the learning happens, so it gets a verdict but doesn't move
the rating.
"""
import hashlib
import json
import random
import re

from . import config

SKILLS = {
    'gist': {'pillar': 'u', 'name': 'Gist'},
    'inference': {'pillar': 'u', 'name': 'Inference'},
    'weak': {'pillar': 'r', 'name': 'Weak steps'},
    'discern': {'pillar': 'r', 'name': 'Fair or trick'},
    'precision': {'pillar': 'e', 'name': 'Precision'},
    'concision': {'pillar': 'e', 'name': 'Concision'},
    'fluency': {'pillar': 's', 'name': 'Fluency'},
}

GAMES = {
    'gist': {'name': 'Gist & Infer', 'skill': 'gist', 'lane': 'graded', 'minutes': 2,
             'blurb': 'Read a passage, then write its point from memory.'},
    'subtext': {'name': 'Subtext', 'skill': 'inference', 'lane': 'graded', 'minutes': 2,
                'blurb': "What's really going on in the scene?"},
    'weak': {'name': 'Find the Weak Step', 'skill': 'weak', 'lane': 'instant', 'minutes': 2,
             'blurb': 'Tap where the reasoning breaks, or call it sound.'},
    'tech': {'name': 'Technique or Fair Move?', 'skill': 'discern', 'lane': 'instant', 'minutes': 2, 'round': 6,
             'blurb': 'Six quick calls: manipulation, or a fair version of the same move?'},
    'word': {'name': "The Author's Word", 'skill': 'precision', 'lane': 'instant', 'minutes': 1,
             'blurb': 'Pick the word the author actually chose.'},
    'bloat': {'name': 'Cut the Bloat', 'skill': 'concision', 'lane': 'graded', 'minutes': 2,
              'blurb': "Cut a padded sentence back to the author's line."},
    'jam': {'name': 'Just a Minute', 'skill': 'fluency', 'lane': 'voice', 'minutes': 2,
            'blurb': 'Sixty seconds without hesitation, repetition or deviation.'},
}

FLAWS = ['unsupported claim', 'overgeneralization', 'false cause', 'false choice', 'loaded or vague word',
         'appeal to authority', 'attack on a person', 'straw man', 'slippery slope', 'circular',
         'irrelevant point', 'none (sound)']
TECHNIQUES = ['emotional manipulation', 'false choice', 'scapegoating', 'fake or irrelevant expert',
              'attack on the person', 'cherry-picking', 'slippery slope', 'conspiracy framing']

# Rubrics: each criterion 0-4 with written anchors. The same text drives Claude's
# grading and my own hand-scoring for the golden set, so the two are comparable.
RUBRICS = {
    'gist': {
        'version': 1,
        'criteria': {
            'main_idea': ['Wrong, or no point at all', 'A detail instead of the point',
                          'The topic, not the point', 'The point, missing one piece', 'The point, complete'],
            'accuracy': ['Contradicts the passage', 'A serious distortion', 'One clear distortion',
                         'Slightly loose', 'Nothing distorted'],
            'concision': ['Says nothing', 'Mostly padding', 'Some padding', 'Tight, one soft spot',
                          'Every word earns its place'],
            'inference': ['Blank or wrong', 'A guess with no basis', 'Partly right',
                          'Right, loosely put', 'Right, matches the key in substance'],
        },
    },
    'subtext': {
        'version': 1,
        'criteria': {
            'inference': ['Wrong or blank', 'Surface reading only', 'Partly right',
                          'Right, loosely put', 'Right, matches the key in substance'],
            'precision': ['Vague', 'Mostly vague', 'Some specifics', 'Specific', 'Specific and well put'],
        },
    },
    'bloat': {
        'version': 1,
        'criteria': {
            'meaning': ['Lost the point', 'Changed the point', 'A nuance lost or added',
                        'Kept, slightly loose', 'Kept exactly'],
        },
    },
    'jam': {
        'version': 1,
        'criteria': {
            'deviation': ['Off the topic', 'Wanders often', 'Wanders now and then', 'On topic, one slip',
                          'On topic, true and logical throughout'],
            'structure': ['No order', 'Hard to follow', 'Some order', 'Clear order', 'Clear order with a landing'],
        },
    },
}

TONES = {
    'soft': 'Be warm and encouraging, but still specific and honest.',
    'balanced': 'Be direct and specific, like a good editor. No flattery.',
    'strict': 'Be exacting, like a tough editor. Hold a high bar and say so plainly.',
}

SENT_RE = re.compile(r'(?<=[.!?…])["”’)]?\s+(?=["“‘(]?[A-Z0-9])')
WORD_RE = re.compile(r"\S+")


def words(text):
    return len(WORD_RE.findall(text or ''))


def split_sentences(text):
    """Sentences with paragraph breaks kept as their own marker '¶'."""
    out = []
    for i, para in enumerate(re.split(r'\n\s*\n', text.strip())):
        if i:
            out.append('¶')
        out.extend(s.strip() for s in SENT_RE.split(para) if s.strip())
    return out


def _norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9 ]+', ' ', (s or '').lower())).strip()


def overlap(a, b):
    """Share of a's words that also appear in b."""
    aw = _norm(a).split()
    bw = set(_norm(b).split())
    return sum(1 for w in aw if w in bw) / len(aw) if aw else 0.0


def stable_shuffle(xs, seed):
    xs = list(xs)
    random.Random(int(hashlib.sha256(seed.encode()).hexdigest()[:12], 16)).shuffle(xs)
    return xs


def golf(diff):
    return {-2: 'Eagle', -1: 'Birdie', 0: 'Par', 1: 'Bogey', 2: 'Double bogey'}.get(
        diff, 'Eagle' if diff < -2 else f'+{diff}')


# ── what the player sees (never the key) ──

def public_payload(item):
    p = json.loads(item['payload'])
    src = json.loads(item['source']) if item['source'] else {}
    out = {'id': item['id'], 'game': item['game'], 'skill': item['skill'], 'source': src, **p}
    if item['game'] == 'weak':
        out['sentences'] = split_sentences(p['passage'])
        out['flaws'] = FLAWS
    if item['game'] == 'tech':
        out['techniques'] = TECHNIQUES
    return out


def reveal(item):
    """The key, for after you've answered."""
    return json.loads(item['key']) if item['key'] else {}


# ── instant scoring ──

def instant(item, answer):
    """Score what code can score. Returns a dict with 'score' (0..1, or None if Claude must grade)."""
    game = item['game']
    key = reveal(item)
    p = json.loads(item['payload'])
    if game == 'weak':
        sents = split_sentences(p['passage'])
        sound = key.get('flaw') == 'none (sound)'
        idx = answer.get('index')
        flaw = answer.get('flaw')
        if sound:
            spot_ok = flaw == 'none (sound)'
            key_idx = None
        else:
            scores = [(i, overlap(key.get('quote', ''), s)) for i, s in enumerate(sents) if s != '¶']
            key_idx = max(scores, key=lambda x: x[1])[0] if scores else None
            spot_ok = idx is not None and 0 <= idx < len(sents) and (
                idx == key_idx or overlap(key.get('quote', ''), sents[idx]) >= 0.5)
        flaw_ok = flaw == key.get('flaw')
        return {'score': (0.5 if spot_ok else 0) + (0.5 if flaw_ok else 0), 'spot_ok': spot_ok,
                'flaw_ok': flaw_ok, 'key_index': key_idx}
    if game == 'word':
        ok = (answer.get('choice') or '').strip().lower() == key['target'].lower()
        return {'score': 1.0 if ok else 0.0, 'ok': ok}
    if game == 'tech':
        kind_ok = answer.get('kind') == key['kind']
        label_ok = key['kind'] == 'technique' and answer.get('technique') == key['technique']
        score = (1.0 if key['kind'] == 'fair' else 0.7 + (0.3 if label_ok else 0)) if kind_ok else 0.0
        conf = answer.get('confidence')
        brier = None
        if isinstance(conf, (int, float)) and 50 <= conf <= 100:
            p_right = conf / 100.0
            brier = round((1 - p_right) ** 2 if kind_ok else p_right ** 2, 4)
        return {'score': score, 'kind_ok': kind_ok, 'label_ok': label_ok, 'brier': brier}
    if game == 'bloat':
        n = words(answer.get('text', ''))
        par = p['par']
        d = n - par
        return {'score': None, 'words': n, 'par': par, 'diff': d, 'golf': golf(d),
                'par_factor': 1.0 if d <= 0 else max(0.0, 1.0 - 0.12 * d)}
    return {'score': None}


# ── Claude grading ──

def _anchor_text(game, anchors):
    if not anchors:
        return ''
    lines = ['Here are answers I scored myself, as calibration for what my scores mean:']
    for a in anchors:
        lines.append(f'- Answer: {json.dumps(a["answer"], ensure_ascii=False)} -> my scores: {json.dumps(a["mine"])}')
    return '\n'.join(lines) + '\n'


def _rubric_text(game):
    r = RUBRICS[game]['criteria']
    return '\n'.join(f'- {name}: ' + '; '.join(f'{i} = {d}' for i, d in enumerate(levels)) for name, levels in r.items())


def grade_request(item, answer, anchors=None, revision_of=None):
    """(prompt, schema, model kind) for Claude, or None if the game needs no grading."""
    game = item['game']
    s = config.settings()
    tone = TONES.get(s.get('grading_tone'), TONES['balanced'])
    who = s.get('reader') or config.DEFAULTS['reader']
    p = json.loads(item['payload'])
    key = reveal(item)
    head = (f'You grade one answer in Binah, a reading, reasoning and writing trainer. The player is {who}. '
            f'{tone} Grade meaning, not phrasing. Never praise or criticise the player as a person. '
            f'Never quote the hidden key back.\n\n')
    if revision_of:
        head += ('This is the player\'s ONE revision after your earlier feedback: '
                 f'{json.dumps(revision_of, ensure_ascii=False)}. Grade the revision on its own merits.\n\n')
    crit_schema = lambda names: {n: {'type': 'integer', 'minimum': 0, 'maximum': 4} for n in names}
    feedback = {'strength': {'type': 'string'}, 'work_on': {'type': 'string'}, 'hint': {'type': 'string'}}
    if game == 'gist':
        names = list(RUBRICS['gist']['criteria'])
        prompt = (head + f'PASSAGE (the player read it, then it was hidden):\n"""\n{p["passage"]}\n"""\n'
                  f'HIDDEN KEY: reference gist: "{key["gist"]}". Key points: '
                  + ' '.join(f'({i + 1}) {k}' for i, k in enumerate(key['key_points']))
                  + f'. Inference question: "{p["inference_q"]}" Key answer: "{key["inference_a"]}"\n\n'
                  + f'PLAYER\'S GIST (20 words max): "{answer.get("gist", "")}"\n'
                  + f'PLAYER\'S INFERENCE ANSWER: "{answer.get("inference", "") or "(blank)"}"\n\n'
                  + 'Score each criterion 0-4 using these anchors:\n' + _rubric_text('gist') + '\n\n'
                  + _anchor_text('gist', anchors)
                  + 'First write "evidence": what the gist actually says against the key, in 1-2 sentences. List the key '
                    'points the gist covers, by number. Then ONE strength (specific, quote the player) and ONE thing to '
                    'work on (name the move), each 25 words max, and a hint toward the missing piece that does NOT give '
                    'the answer away.')
        schema = {'type': 'object', 'properties': {'evidence': {'type': 'string'}, **crit_schema(names),
                                                   'covered': {'type': 'array', 'items': {'type': 'integer'}}, **feedback},
                  'required': ['evidence', *names, 'covered', 'strength', 'work_on', 'hint']}
        return prompt, schema, 'main'
    if game == 'subtext':
        names = list(RUBRICS['subtext']['criteria'])
        prompt = (head + f'PASSAGE:\n"""\n{p["passage"]}\n"""\nQUESTION: "{p["question"]}"\n'
                  f'HIDDEN KEY: "{key["answer"]}" (it shows in: "{key.get("evidence_quote", "")}")\n'
                  f'PLAYER\'S ANSWER: "{answer.get("text", "")}"\n\n'
                  'Score each criterion 0-4:\n' + _rubric_text('subtext') + '\n\n' + _anchor_text('subtext', anchors)
                  + 'First write "evidence" (1-2 sentences comparing the answer with the key), then one strength and one '
                    'thing to work on, 25 words max each, and a hint that does not give the answer away.')
        schema = {'type': 'object', 'properties': {'evidence': {'type': 'string'}, **crit_schema(names), **feedback},
                  'required': ['evidence', *names, 'strength', 'work_on', 'hint']}
        return prompt, schema, 'main'
    if game == 'bloat':
        prompt = (head + 'A good author wrote the ORIGINAL; someone padded it; the player cut the padded version back down. '
                  'Judge ONLY whether the player\'s version keeps the ORIGINAL\'s meaning (not style, not length).\n'
                  f'ORIGINAL: "{key["original"]}"\nPADDED: "{p["padded"]}"\nPLAYER: "{answer.get("text", "")}"\n\n'
                  'Score meaning 0-4:\n' + _rubric_text('bloat') + '\n\n' + _anchor_text('bloat', anchors)
                  + 'Then one strength and one thing to work on (name the cut, e.g. "nominalisation: \'made a decision\' -> '
                    '\'decided\'"), 25 words max each.')
        schema = {'type': 'object', 'properties': {'evidence': {'type': 'string'}, 'meaning': {'type': 'integer', 'minimum': 0, 'maximum': 4},
                                                   'strength': {'type': 'string'}, 'work_on': {'type': 'string'}},
                  'required': ['evidence', 'meaning', 'strength', 'work_on']}
        return prompt, schema, 'quick'
    if game == 'weak':
        why = (answer.get('why') or '').strip()
        if not why:
            return None
        prompt = (head + f'PASSAGE:\n"""\n{p["passage"]}\n"""\nHIDDEN KEY: weakest step "{key.get("quote", "")}" '
                  f'({key.get("flaw")}): {key.get("explain", "")} Hidden assumption: {key.get("assumption", "")}\n'
                  f'PLAYER\'S ONE-LINE REASON: "{why}"\n\nScore 0-4 how well the reason identifies the real problem '
                  '(paraphrase is fine), with one sentence of feedback, 25 words max.')
        schema = {'type': 'object', 'properties': {'evidence': {'type': 'string'}, 'reason': {'type': 'integer', 'minimum': 0, 'maximum': 4},
                                                   'work_on': {'type': 'string'}}, 'required': ['evidence', 'reason', 'work_on']}
        return prompt, schema, 'quick'
    if game == 'jam':
        names = list(RUBRICS['jam']['criteria'])
        m = answer.get('metrics', {})
        prompt = (head + 'This is "Just a Minute": speak for 60 seconds on the topic without hesitation, repetition or '
                  'deviation. Code already counted hesitation and repetition; you judge only DEVIATION (off-topic, '
                  'untrue, or illogical) and STRUCTURE.\n'
                  f'TOPIC: "{p["topic"]}"\nTRANSCRIPT (clean): "{answer.get("text", "")}"\n'
                  f'MEASURED: {json.dumps({k: m.get(k) for k in ("speaking_time", "wpm", "fillers_per_min", "long_pauses", "repeats")})}\n\n'
                  'Score each 0-4:\n' + _rubric_text('jam') + '\n\n' + _anchor_text('jam', anchors)
                  + 'List up to 3 exact phrases that deviated (or none). Then one strength and one thing to work on, '
                    '25 words max each.')
        schema = {'type': 'object', 'properties': {'evidence': {'type': 'string'}, **crit_schema(names),
                                                   'deviations': {'type': 'array', 'items': {'type': 'string'}},
                                                   'strength': {'type': 'string'}, 'work_on': {'type': 'string'}},
                  'required': ['evidence', *names, 'deviations', 'strength', 'work_on']}
        return prompt, schema, 'main'
    return None


def clamp4(v):
    try:
        return max(0, min(4, int(v)))
    except (TypeError, ValueError):
        return 0


def final_score(item, inst, grade):
    """Combine code and Claude into 0..1."""
    game = item['game']
    if game in ('weak', 'word', 'tech'):
        return inst.get('score') or 0.0
    if not grade:
        return None
    if game == 'gist':
        return sum(clamp4(grade.get(k)) for k in RUBRICS['gist']['criteria']) / 16.0
    if game == 'subtext':
        return (0.7 * clamp4(grade.get('inference')) + 0.3 * clamp4(grade.get('precision'))) / 4.0
    if game == 'bloat':
        return inst.get('par_factor', 1.0) * clamp4(grade.get('meaning')) / 4.0
    if game == 'jam':
        return (jam_code_scores(inst)['hesitation'] + jam_code_scores(inst)['repetition']
                + clamp4(grade.get('deviation')) + clamp4(grade.get('structure'))) / 16.0
    return None


def jam_code_scores(inst):
    """Hesitation and repetition, 0-4 each, from the transcript's numbers."""
    m = inst.get('metrics', {})
    lp = m.get('long_pauses', 0) or 0
    fpm = m.get('fillers_per_min', 0) or 0
    hes = 4 if lp <= 1 and fpm <= 4 else 3 if lp <= 2 and fpm <= 7 else 2 if lp <= 4 and fpm <= 10 else 1 if lp <= 6 else 0
    reps = len(m.get('repeats') or [])
    rep = max(0, 4 - reps)
    spoken = m.get('speaking_time', m.get('duration', 0)) or 0
    if spoken < 40:                      # stopped well short of the minute
        hes = min(hes, 1)
    return {'hesitation': hes, 'repetition': rep}
