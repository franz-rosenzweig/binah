"""Binah's command line.

    python -m binah.cli set-password [--user NAME]   # set the login (prompts for the password)
    python -m binah.cli import                         # load items from the engine and content/
    python -m binah.cli doctor                         # what's configured, what's live, the queue
    python -m binah.cli golden                         # the golden-set agreement report
"""
import argparse
import getpass
import json
import sys

from . import auth, config, db, golden, items


def main():
    ap = argparse.ArgumentParser(prog='binah')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sp = sub.add_parser('set-password')
    sp.add_argument('--user')
    sub.add_parser('import')
    sub.add_parser('doctor')
    sub.add_parser('golden')
    a = ap.parse_args()
    if a.cmd == 'set-password':
        pw = getpass.getpass('New password: ') if sys.stdin.isatty() else sys.stdin.readline().rstrip('\n')
        if len(pw) < 10:
            sys.exit('Use at least 10 characters.')
        auth.set_password(pw, user=a.user, rotate=True)
        print(f'Password set for "{auth.username()}". Every browser is signed out.')
    elif a.cmd == 'import':
        print(json.dumps(items.import_all(), indent=2))
    elif a.cmd == 'doctor':
        c = db.connect()
        s = config.settings()
        print('state     ', config.STATE)
        print('hosts     ', config.HOSTS, 'port', config.PORT)
        print('login     ', 'set' if auth.has_password() else 'NOT SET (run set-password)', '·', auth.username())
        print('model     ', config.model('main'), '/', config.model('validator'), '/', config.model('quick'))
        print('passages  ', config.PASSAGES_DB, 'exists' if config.PASSAGES_DB.exists() else 'missing')
        print('live items', dict(c.execute("select game, count(*) from items where status='live' group by game").fetchall()))
        print('drafts    ', dict(c.execute("select game, count(*) from items where status='draft' group by game").fetchall()))
        print('jobs      ', dict(c.execute("select status, count(*) from jobs group by status").fetchall()))
        print('export    ', s.get('export_dir') or 'off')
    elif a.cmd == 'golden':
        print(json.dumps(golden.report(db.connect()), indent=2))


if __name__ == '__main__':
    main()
