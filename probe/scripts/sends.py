#!/usr/bin/env python3
"""Summarises each click on Send in a collected round: the Sign state, what the send check got,
how many send-time encode() calls ran and how long each took.

Usage: python3 probe/scripts/sends.py probe/test-results/<timestamp> [...]

A send with no row here never reached the extension, as in t31.
"""

import json
import pathlib
import sys


def summarise(results):
    rows = [json.loads(line) for line in open(results / 'events.jsonl')]
    print(f'== {results}')
    for check in (r for r in rows if r['event'] == 'compose-can-send'):
        context = check['contextID']
        encodes = [r for r in rows if r.get('event') == 'encode-marked' and r.get('contextID') == context and r['state'] == 2]
        sequences = {e.get('sequence') for e in encodes}
        finished = [r for r in rows if r.get('event') == 'encode-finished' and r.get('sequence') in sequences]
        elapsed = [round(f.get('elapsedSeconds', 0), 1) for f in finished]
        print(f"  {check['time'][11:19]} marker={check.get('marker')!r:22} sign={check['shouldSign']!s:5} "
              f"sendCheckBytes={check['rawBytes']:>9} sendEncodes={len(encodes)} elapsed={elapsed} "
              f"ctx={context[:6]}")


for path in sys.argv[1:]:
    summarise(pathlib.Path(path))
