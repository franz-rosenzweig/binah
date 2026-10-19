"""Measure a passage: plain, explainable numbers, no model calls.

Everything here is cheap enough to run over a whole library. The numbers feed
two things: a difficulty estimate (the item's starting rating before play
calibrates it) and a fit score for each game (how good a candidate the
passage is for Gist, Argument, Subtext and so on). Claude only looks at the
best candidates afterwards.
"""
import math
import re
from functools import lru_cache

from wordfreq import zipf_frequency

WORD_RE = re.compile(r"[A-Za-z][A-Za-z'’\-]*")
SENT_SPLIT_RE = re.compile(r'(?<=[.!?…])["”’)\]]*\s+(?=["“‘(\[]?[A-Z0-9])')

STOP = set("""a an the and or but if then so of to in on at by for with from as is are was were be been being
it its this that these those he she they them his her their we us our you your i me my mine not no nor
do does did done have has had having can could will would shall should may might must there here what which who
whom whose when where why how all any each every some such only own same than too very just also into over
under again further once about above below up down out off more most other both few many much one two
because while until though although yet still even ever never always often per via upon onto unto am s t""".split())

CONNECTIVES = {
    'causal': ['because', 'since', 'therefore', 'thus', 'hence', 'consequently', 'as a result',
               'accordingly', 'which means', 'so that', 'that is why', 'for this reason', 'due to'],
    'contrast': ['but', 'however', 'yet', 'although', 'though', 'whereas', 'nevertheless', 'nonetheless',
                 'instead', 'on the other hand', 'rather than', 'in contrast', 'conversely'],
    'concession': ['admittedly', 'granted', 'of course', 'to be sure', 'even if', 'even though',
                   'it is true that', 'no doubt'],
    'claim': ['should', 'must', 'ought', 'need to', 'cannot', 'never', 'always', 'the problem is',
              'the point is', 'the truth is', 'in fact', 'clearly', 'surely', 'it follows'],
    'example': ['for example', 'for instance', 'such as', 'consider', 'imagine', 'take the case'],
    'conclusion': ['in short', 'in other words', 'ultimately', 'in the end', 'to sum up', 'this means',
                   'what this shows', 'the lesson'],
    'hedge': ['perhaps', 'maybe', 'might', 'seems', 'seem', 'arguably', 'likely', 'possibly', 'probably',
              'suggests', 'appears'],
}
_CONN_RE = {k: re.compile(r'\b(' + '|'.join(re.escape(p) for p in v) + r')\b', re.I) for k, v in CONNECTIVES.items()}

PRONOUN_OPEN = {'he', 'she', 'it', 'they', 'this', 'that', 'these', 'those', 'his', 'her', 'their', 'its',
                'him', 'them', 'such', 'there'}
CONJ_OPEN = {'but', 'and', 'so', 'yet', 'or', 'then', 'also', 'still', 'thus', 'therefore', 'however',
             'nor', 'besides', 'moreover', 'furthermore', 'meanwhile', 'instead', 'otherwise'}
PAST = {'was', 'were', 'had', 'said', 'went', 'came', 'saw', 'took', 'made', 'knew', 'thought', 'felt',
        'looked', 'told', 'asked', 'got', 'gave', 'found', 'left', 'stood', 'sat', 'turned', 'began',
        'seemed', 'heard', 'ran', 'walked', 'smiled', 'nodded', 'did'}
PRESENT = {'is', 'are', 'does', 'do', 'has', 'have', 'can', 'will', 'should', 'must', 'may', 'need', 'means'}
ABSTRACT_RE = re.compile(r'(tion|sion|ness|ity|ism|ment|ance|ence|hood|ship|ology|ality)s?$')
QUOTE_RE = re.compile(r'[“"]([^”"]{2,})[”"]')


@lru_cache(maxsize=200000)
def zipf(word):
    return zipf_frequency(word, 'en')


def syllables(word):
    w = word.lower().strip("'’-")
    if not w:
        return 0
    if len(w) <= 3:
        return 1
    w = re.sub(r'(?:[^laeiouy]es|ed|[^laeiouy]e)$', '', w)
    w = re.sub(r'^y', '', w)
    return max(1, len(re.findall(r'[aeiouy]{1,2}', w)))


def sentences(text):
    parts = [s.strip() for s in SENT_SPLIT_RE.split(text) if s.strip()]
    return parts or [text]


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def bell(x, lo, peak_lo, peak_hi, hi):
    """1 inside [peak_lo, peak_hi], falling linearly to 0 at lo and hi."""
    if x <= lo or x >= hi:
        return 0.0
    if x < peak_lo:
        return (x - lo) / (peak_lo - lo)
    if x > peak_hi:
        return (hi - x) / (hi - peak_hi)
    return 1.0


def measure(text):
    sents = sentences(text)
    words = WORD_RE.findall(text)
    nw = len(words) or 1
    ns = len(sents) or 1
    lower = [w.lower().strip("'’") for w in words]
    syl = sum(syllables(w) for w in words)
    sent_lens = [len(WORD_RE.findall(s)) for s in sents]

    # Proper nouns: capitalised words that don't start a sentence.
    starts = set()
    for s in sents:
        m = WORD_RE.search(s)
        if m:
            starts.add(m.start() + text.find(s) if text.find(s) >= 0 else -1)
    proper = 0
    content = []
    for m in WORD_RE.finditer(text):
        w = m.group(0)
        lw = w.lower().strip("'’")
        if w[0].isupper() and lw != 'i' and m.start() not in starts:
            proper += 1
            continue
        if lw not in STOP and len(lw) > 2:
            content.append(lw)
    zs = [zipf(w.replace('’', "'")) for w in content] or [5.0]
    rare = sum(1 for z in zs if z < 3.0) / len(zs)
    very_rare = sum(1 for z in zs if z < 2.0) / len(zs)

    conn = {k: len(r.findall(text)) for k, r in _CONN_RE.items()}
    per100 = lambda n: 100.0 * n / nw
    arg_markers = conn['causal'] + conn['contrast'] + conn['concession'] + conn['claim'] + conn['conclusion']

    quoted = sum(len(m.group(1)) for m in QUOTE_RE.finditer(text))
    dialogue = clamp(quoted / max(1, len(text)))

    first = WORD_RE.search(text)
    first_word = first.group(0).lower() if first else ''
    first_sent = sents[0] if sents else ''

    past = sum(1 for w in lower if w in PAST or (w.endswith('ed') and len(w) > 4))
    present = sum(1 for w in lower if w in PRESENT)
    i_rate = sum(1 for w in lower if w in ('i', 'me', 'my', 'mine')) / nw
    we_rate = sum(1 for w in lower if w in ('we', 'us', 'our', 'ours')) / nw
    you_rate = sum(1 for w in lower if w in ('you', 'your', 'yours')) / nw
    abstract = sum(1 for w in content if len(w) > 6 and ABSTRACT_RE.search(w)) / nw

    fkgl = 0.39 * (nw / ns) + 11.8 * (syl / nw) - 15.59
    ease = 206.835 - 1.015 * (nw / ns) - 84.6 * (syl / nw)

    f = {
        'words': nw, 'sentences': ns,
        'avg_sent': round(nw / ns, 1), 'max_sent': max(sent_lens) if sent_lens else nw,
        'fkgl': round(fkgl, 1), 'ease': round(ease, 1),
        'zipf_mean': round(sum(zs) / len(zs), 2), 'rare': round(rare, 3), 'very_rare': round(very_rare, 3),
        'proper_per100': round(per100(proper), 1),
        'digits': len(re.findall(r'\d', text)),
        'dialogue': round(dialogue, 2),
        'questions': text.count('?'),
        'pronoun_open': first_word in PRONOUN_OPEN,
        'conj_open': first_word in CONJ_OPEN,
        'refers_back': bool(re.match(r'^\s*(This|These|That|Those|Such|It|Here)\b', first_sent)) and len(sents) > 1,
        'ends_clean': bool(re.search(r'[.!?…]["”’)]?\s*$', text)),
        'past_rate': round(past / nw, 3), 'present_rate': round(present / nw, 3),
        'i_rate': round(i_rate, 3), 'we_rate': round(we_rate, 3), 'you_rate': round(you_rate, 3),
        'abstract': round(abstract, 3),
        'conn': conn, 'arg_per100': round(per100(arg_markers), 2),
        'content_ratio': round(len(content) / nw, 2),
    }
    f['kind'] = classify(f)
    f['difficulty'] = difficulty(f)
    return f


def classify(f):
    if f['dialogue'] > 0.33:
        return 'dialogue'
    narrative = f['past_rate'] > 0.045 and f['present_rate'] < 0.03
    if f['arg_per100'] >= 3.0 and f['present_rate'] >= 0.02 and not narrative:
        return 'argument'
    if narrative:
        return 'narrative'
    return 'exposition'


def difficulty(f):
    """0-100. Readability, rare words, long sentences, abstraction and argument density."""
    fk = clamp((f['fkgl'] - 4) / 14)
    rare = clamp(f['rare'] / 0.14)
    sl = clamp((f['avg_sent'] - 10) / 25)
    ab = clamp(f['abstract'] / 0.08)
    ar = clamp(f['arg_per100'] / 6)
    return round(100 * (0.30 * fk + 0.25 * rare + 0.20 * sl + 0.15 * ab + 0.10 * ar), 1)


def start_rating(f):
    """Starting Elo for an item built on this passage: 800 (easy) to 1600 (dense)."""
    return round(800 + 8 * f['difficulty'])


def self_contained(f):
    s = 1.0
    if f['pronoun_open']:
        s -= 0.45
    if f['conj_open']:
        s -= 0.35
    if f['refers_back']:
        s -= 0.25
    if not f['ends_clean']:
        s -= 0.3
    return clamp(s)


def fits(f, highlighted=False):
    """Fit score 0-1 for each game this passage could feed."""
    sc = self_contained(f)
    kind = f['kind']
    boost = 1.15 if highlighted else 1.0
    no_dialogue = 1 - clamp(f['dialogue'] * 2.5)
    readable = 1 - clamp((f['digits'] - 6) / 20)
    out = {}
    out['gist'] = clamp(bell(f['words'], 90, 140, 230, 330) * sc * no_dialogue
                        * {'exposition': 1.0, 'argument': 1.0, 'narrative': 0.45, 'dialogue': 0.1}[kind]
                        * (0.55 + 0.45 * clamp(f['arg_per100'] / 3 + f['abstract'] * 6)) * readable * boost, 0, 1.2)
    out['argument'] = clamp(bell(f['words'], 70, 110, 230, 320) * sc * no_dialogue
                            * (1.0 if kind == 'argument' else 0.35 if kind == 'exposition' else 0.05)
                            * clamp(f['arg_per100'] / 5) * (0.7 + 0.3 * clamp((f['conn']['claim'] + f['conn']['causal']) / 3))
                            * boost, 0, 1.2)
    out['subtext'] = clamp(bell(f['words'], 100, 150, 300, 420) * bell(f['dialogue'], 0.15, 0.3, 0.75, 0.95)
                           * (1.0 if kind in ('dialogue', 'narrative') else 0.3) * (1 if f['ends_clean'] else 0.6) * boost, 0, 1.2)
    out['blueprint'] = clamp(bell(f['sentences'], 3, 5, 7, 10) * bell(f['avg_sent'], 7, 12, 26, 38) * sc * no_dialogue
                             * clamp((f['conn']['causal'] + f['conn']['contrast'] + f['conn']['example']
                                      + f['conn']['conclusion']) / max(1, f['sentences'] - 1) * 1.6)
                             * (1.0 if kind in ('exposition', 'argument') else 0.3) * boost, 0, 1.2)
    out['listen'] = clamp(bell(f['words'], 80, 110, 190, 260) * sc * readable
                          * (1.0 if kind in ('narrative', 'exposition') else 0.5)
                          * bell(f['fkgl'], 2, 5, 11, 16) * (1 - clamp(f['proper_per100'] / 12)) * boost, 0, 1.2)
    return {k: round(v, 3) for k, v in out.items()}


def author_word(sentence):
    """Mot Juste candidate: the most precise ordinary word in a sentence, or None.

    Moderately rare (Zipf 2.4-4.0), lower case, not a name, at least five
    letters. The author's choice becomes the answer; Claude writes the decoys.
    """
    best = None
    words = list(WORD_RE.finditer(sentence))
    for i, m in enumerate(words):
        w = m.group(0)
        lw = w.lower()
        if i == 0 or not w.islower() or len(w) < 5 or "'" in w or '’' in w or '-' in w or lw in STOP:
            continue
        z = zipf(lw)
        if 2.4 <= z <= 4.0:
            score = 1 - abs(z - 3.2) / 1.0
            if best is None or score > best[1]:
                best = (w, round(score, 3), round(z, 2))
    return best


def sentence_fits(sentence):
    """Sentence-level games: Mot Juste (author's word) and Cut the Bloat (author's tight line)."""
    words = WORD_RE.findall(sentence)
    n = len(words)
    if n < 8 or n > 40 or QUOTE_RE.search(sentence) or not re.search(r'[.!?]["”’)]?$', sentence.strip()):
        return None
    first = words[0].lower()
    if first in PRONOUN_OPEN or first in CONJ_OPEN:
        return None
    content = [w for w in words if w.lower() not in STOP and len(w) > 2]
    ratio = len(content) / n
    out = {'words': n, 'content_ratio': round(ratio, 2)}
    aw = author_word(sentence)
    if aw:
        out['motjuste'] = round(aw[1] * bell(n, 8, 12, 28, 40), 3)
        out['target'] = aw[0]
        out['target_zipf'] = aw[2]
    out['tight'] = round(clamp((ratio - 0.4) / 0.3) * bell(n, 9, 12, 26, 34), 3)
    return out
