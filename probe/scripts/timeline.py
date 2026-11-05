#!/usr/bin/env python3
"""Prints a collected round's events in order, with the fields that matter for analysis.

Usage: python3 probe/scripts/timeline.py probe/test-results/<timestamp> [--since HH:MM:SS]

Times are UTC, as logged. Repeated status events for the same marker and the frequent
decode-called events are left out.
"""

import argparse
import json
import pathlib

FIELDS = ('marker', 'state', 'call', 'sequence', 'rawBytes', 'shouldSign', 'returnedBytes', 'strippedParts',
          'notedPlain', 'notedHTML', 'elapsedSeconds', 'file', 'characters', 'viaMessageID', 'files', 'isAutoSave',
          'reportedCanEncode', 'seconds')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('results', type=pathlib.Path)
    parser.add_argument('--since', default='', help='only events at or after this UTC time, as HH:MM:SS')
    args = parser.parse_args()

    rows = [json.loads(line) for line in open(args.results / 'events.jsonl')]
    print(f"{len(rows)} events, extension process IDs: {sorted({r.get('pid') for r in rows})}")
    last_status = None
    for r in rows:
        event = r.get('event')
        if event == 'decode-called' or r['time'][11:19] < args.since:
            continue
        if event == 'status':
            if r.get('marker') == last_status:
                continue
            last_status = r.get('marker')
        shown = {k: r[k] for k in FIELDS if k in r}
        if 'contextID' in r:
            shown['ctx'] = r['contextID'][:6]
        if 'messageID' in r:
            shown['msg'] = r['messageID'][:6]
        if 'elapsedSeconds' in shown:
            shown['elapsedSeconds'] = round(shown['elapsedSeconds'], 2)
        print(r['time'][11:23], event, shown)


if __name__ == '__main__':
    main()
