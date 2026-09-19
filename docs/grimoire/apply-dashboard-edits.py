#!/usr/bin/env python3
"""Apply a dashboard-edits-*.json export (from the dashboard's Edit mode) to the HTML file.

    python3 apply-dashboard-edits.py ~/Downloads/dashboard-edits-2026-09-19.json
    python3 apply-dashboard-edits.py <file.json> --dry-run

Each edit is an exact `before` -> `after` replacement of an element's inner HTML.
Nothing is written unless every edit is unambiguous, so a partial apply can't happen.
"""
import json, sys, pathlib

HTML = pathlib.Path(__file__).with_name('dm-dashboard-doomed-forgotten-realms.html')

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    dry = '--dry-run' in sys.argv
    if not args:
        sys.exit(__doc__)

    payload = json.loads(pathlib.Path(args[0]).expanduser().read_text())
    edits = payload.get('edits', payload if isinstance(payload, list) else [])
    html = HTML.read_text()

    ok, already, problems = [], [], []
    for i, ed in enumerate(edits, 1):
        before, after = ed['before'].strip(), ed['after'].strip()
        where = f"{ed.get('page','?')} / {ed.get('section','') or '—'}"
        # `after` is checked first: `before` is often a substring of `after`
        # (e.g. text appended to a sentence), so a count-based check alone
        # would happily apply the same edit twice.
        if after in html:
            already.append((i, where, 'already applied'))
            continue
        hits = html.count(before)
        if hits == 1:
            ok.append((i, before, after, where))
        elif hits == 0:
            already.append((i, where, 'NOT FOUND'))
        else:
            problems.append((i, where, f'{hits} matches — ambiguous'))

    for i, where, why in already:
        print(f'  skip  #{i:<3} {where}  ({why})')
    for i, where, why in problems:
        print(f'  STOP  #{i:<3} {where}  ({why})')
    if problems:
        sys.exit(f'\n{len(problems)} ambiguous edit(s); nothing written. Resolve by hand.')

    for i, before, after, where in ok:
        html = html.replace(before, after, 1)
        print(f'  ok    #{i:<3} {where}')
        print(f'         - {before[:100]}')
        print(f'         + {after[:100]}')

    notfound = [x for x in already if x[2] == 'NOT FOUND']
    if notfound:
        print(f'\n⚠️  {len(notfound)} edit(s) matched nothing and were not applied — check these by hand.')

    if dry:
        print(f'\nDRY RUN — {len(ok)} edit(s) would be applied.')
        return
    if ok:
        HTML.write_text(html)
    print(f'\nApplied {len(ok)} edit(s); skipped {len(already)}.')
    if ok:
        print('Tell Rebekah to hit "Discard all edits" once the change is live, or just reload — '
              'applied edits self-clear from her browser.')

if __name__ == '__main__':
    main()
