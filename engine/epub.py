"""Pull readable text out of an EPUB, in reading order, as blocks.

Only the standard library: an EPUB is a zip of XHTML files plus an OPF file
that gives the reading order (the "spine"). We keep paragraphs and headings,
drop footnote markers, scripts and navigation, and tag each spine document
as front matter, back matter or body so the miner can skip copyright pages,
tables of contents, indexes and notes.
"""
import posixpath
import re
import zipfile
from html.parser import HTMLParser
from xml.etree import ElementTree as ET

BLOCK = {'p', 'div', 'li', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
         'td', 'dd', 'dt', 'pre', 'section', 'article', 'figure'}
HEADING = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}
SKIP = {'script', 'style', 'head', 'title', 'nav', 'sup', 'figcaption', 'svg', 'math'}
NOTE_TYPES = ('noteref', 'footnote', 'endnote', 'rearnote', 'annoref')

# File names and headings that mark matter we never quote from.
FRONT_RE = re.compile(r'(cover|title|copyright|toc|contents|dedication|epigraph|halftitle|'
                      r'frontmatter|front-matter|praise|also-?by|nav|colophon|imprint)', re.I)
BACK_RE = re.compile(r'(index|notes|endnotes|bibliograph|references|acknowledg|about[-_ ]?the[-_ ]?author|'
                     r'backmatter|back-matter|glossary|appendix|permissions|credits|further[-_ ]reading|'
                     r'reading[-_ ]group|discussion|excerpt|preview|newsletter)', re.I)
HEAD_SKIP_RE = re.compile(r'^\s*(contents|table of contents|copyright|dedication|acknowledg(e)?ments?|'
                          r'index|notes|endnotes|bibliography|references|about the author|also by|'
                          r'praise for|further reading|permissions|glossary)\b', re.I)


class _Blocks(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []          # (kind, text)
        self.buf = []
        self.kind = 'p'
        self.skip_stack = []

    def _flush(self):
        text = re.sub(r'\s+', ' ', ''.join(self.buf)).strip()
        if text:
            self.blocks.append((self.kind, text))
        self.buf = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        etype = (a.get('epub:type') or a.get('role') or '').lower()
        if self.skip_stack:
            if tag == self.skip_stack[-1][0]:
                self.skip_stack[-1][1] += 1
            return
        if tag in SKIP or any(t in etype for t in NOTE_TYPES) or 'doc-noteref' in etype:
            self.skip_stack.append([tag, 1])
            return
        if tag in BLOCK:
            self._flush()
            self.kind = 'h' if tag in HEADING else ('quote' if tag == 'blockquote' else 'p')
        elif tag == 'br':
            self.buf.append(' ')

    def handle_startendtag(self, tag, attrs):
        if tag == 'br' and not self.skip_stack:
            self.buf.append(' ')

    def handle_endtag(self, tag):
        if self.skip_stack:
            top = self.skip_stack[-1]
            if tag == top[0]:
                top[1] -= 1
                if top[1] == 0:
                    self.skip_stack.pop()
            return
        if tag in BLOCK:
            self._flush()
            self.kind = 'p'

    def handle_data(self, data):
        if not self.skip_stack:
            self.buf.append(data)

    def close(self):
        super().close()
        self._flush()


def _opf_path(z):
    root = ET.fromstring(z.read('META-INF/container.xml'))
    for el in root.iter():
        if el.tag.endswith('rootfile'):
            return el.attrib['full-path']
    raise ValueError('no rootfile in container.xml')


def spine_docs(path):
    """Yield (href, role, blocks) in reading order. role is front, body or back."""
    with zipfile.ZipFile(path) as z:
        opf = _opf_path(z)
        base = posixpath.dirname(opf)
        root = ET.fromstring(z.read(opf))
        manifest, spine, guide = {}, [], {}
        for el in root.iter():
            t = el.tag.split('}')[-1]
            if t == 'item':
                manifest[el.attrib.get('id')] = (el.attrib.get('href', ''), el.attrib.get('media-type', ''),
                                                 el.attrib.get('properties', ''))
            elif t == 'itemref' and el.attrib.get('linear', 'yes') != 'no':
                spine.append(el.attrib.get('idref'))
            elif t == 'reference':
                guide[el.attrib.get('href', '').split('#')[0]] = el.attrib.get('type', '')
        names = set(z.namelist())
        n = len(spine)
        for i, idref in enumerate(spine):
            href, mtype, props = manifest.get(idref, ('', '', ''))
            if not href or 'html' not in mtype:
                continue
            full = posixpath.normpath(posixpath.join(base, href)) if base else href
            if full not in names:
                continue
            try:
                raw = z.read(full).decode('utf-8', errors='replace')
            except KeyError:
                continue
            p = _Blocks()
            try:
                p.feed(raw)
                p.close()
            except Exception:
                continue
            blocks = p.blocks
            role = 'body'
            gtype = guide.get(href, '')
            first_head = next((t for k, t in blocks if k == 'h'), '')
            if 'nav' in props or gtype in ('toc', 'cover', 'title-page', 'copyright-page', 'dedication'):
                role = 'front'
            elif gtype in ('index', 'notes', 'bibliography', 'acknowledgements', 'colophon'):
                role = 'back'
            elif HEAD_SKIP_RE.match(first_head or ''):
                role = 'back' if i > n / 2 else 'front'
            elif FRONT_RE.search(posixpath.basename(href)) and i < n * 0.25:
                role = 'front'
            elif BACK_RE.search(posixpath.basename(href)) and i > n * 0.5:
                role = 'back'
            yield href, role, blocks


def chapters(path):
    """Group body text into chapters: (chapter_title, [paragraph, ...])."""
    out = []
    for href, role, blocks in spine_docs(path):
        if role != 'body':
            continue
        title, paras = None, []
        for kind, text in blocks:
            if kind == 'h':
                if paras:
                    out.append((title or posixpath.basename(href), paras))
                    paras = []
                title = text[:120]
            else:
                paras.append(text)
        if paras:
            out.append((title or posixpath.basename(href), paras))
    return out
