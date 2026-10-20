"""Put together the public taste of Binah: one game that runs entirely in the browser.

    python3 tools/build_demo.py OUT_DIR

OUT_DIR gets demo/ (the page, its script and screenshots), the app's style.css with
font paths made relative, the fonts, the icon, and content/technique.json. No server and
nothing from the private state: every file comes from this repo.
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for p in (ROOT / 'demo').iterdir():
        if p.is_dir():
            shutil.copytree(p, out / p.name, dirs_exist_ok=True)
        else:
            shutil.copy2(p, out / p.name)
    css = (ROOT / 'web' / 'style.css').read_text().replace('url(/fonts/', 'url(fonts/')
    (out / 'style.css').write_text(css)
    (out / 'fonts').mkdir(exist_ok=True)
    for f in (ROOT / 'web' / 'fonts').glob('*.woff2'):
        shutil.copy2(f, out / 'fonts' / f.name)
    shutil.copy2(ROOT / 'web' / 'icon.svg', out / 'icon.svg')
    shutil.copy2(ROOT / 'content' / 'technique.json', out / 'technique.json')
    print(f'demo written to {out}')


if __name__ == '__main__':
    main()
