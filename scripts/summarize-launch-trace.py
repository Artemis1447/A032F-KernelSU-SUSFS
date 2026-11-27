#!/usr/bin/env python3
"""Summarize bounded A03 Core launch traces without storing task names in results."""

import argparse
import gzip
import json
import re
from collections import Counter
from pathlib import Path


EVENT = re.compile(r'^[ \t]*.*?-(\d+)\s+\[\d+\]\s+\S+\s+(\d+\.\d+): (\w+): (.*)$', re.M)


def fields(text):
    return dict(re.findall(r'(\w+)=([^\s]+)', text))


def analyze(sample, text):
    tids = [int(n) for n in re.search(r'^# settings tids: (.+)$', text, re.M)[1].split()]
    leader = re.search(r'^# settings pid: (\d+)$', text, re.M)
    main_tid = int(leader[1]) if leader else tids[0]  # procfs emits the leader first in the existing captures.
    persistent = set(map(int, re.search(r'^# persistent tids: (.+)$', text, re.M)[1].split()))
    entries, written = map(int, re.search(r'entries-in-buffer/entries-written: (\d+)/(\d+)', text).groups())
    rows = [(float(clock), int(pid), name, data) for pid, clock, name, data in EVENT.findall(text)]
    marks = {d: t for t, _, e, d in rows if e == 'tracing_mark_write'}
    start, end = (marks[f'a3core_launch_{mark}'] for mark in ('begin', 'end'))
    prefs = [float(t) for t in re.findall(r'^\s*(\d+\.\d+)\s+' + str(main_tid) +
                                          r'\s+\d+ .*All preferences added', text, re.M)]
    displayed = [float(t) for t in re.findall(r'^\s*(\d+\.\d+)\s+\d+\s+\d+.*Displayed com\.android\.settings/', text, re.M)]
    totals = Counter()
    events = Counter()
    main_state = None
    transition = None
    active = {}
    waits = Counter()
    longest = Counter()

    def mark(now, state):
        nonlocal transition, main_state
        if transition is not None:
            totals[main_state] += now - transition
        transition, main_state = now, state

    for now, actor, name, data in rows:
        if not start <= now <= end:
            continue
        f = fields(data)
        if name == 'sched_switch':
            if int(f['prev_pid']) == main_tid:
                mark(now, 'runnable' if f['prev_state'].startswith('R') else 'blocked')
            elif int(f['next_pid']) == main_tid:
                mark(now, 'running')
        elif name == 'sched_wakeup' and int(f['pid']) == main_tid and main_state == 'blocked':
            mark(now, 'runnable')
        elif name == 'sched_migrate_task':
            events['migrations'] += 1
            if int(f['pid']) in tids:
                events['settings_migrations'] += 1
                if int(f['orig_cpu']) // 4 != int(f['dest_cpu']) // 4:
                    events['settings_cross_cluster'] += 1
        elif name == 'cpu_frequency':
            events['frequency_events'] += 1
        elif name.startswith('block_rq_') and data.startswith('179,0 '):
            events[name] += 1
        elif name.startswith(('dma_fence_wait_', 'mm_vmscan_direct_reclaim_')):
            if name.startswith('dma_fence'):
                group = 'fence'
                identity = (actor, f.get('context'), f.get('seqno'))
                begin = name.endswith('_start')
            else:
                group = 'reclaim'
                identity = (actor,)
                begin = name.endswith('_begin')
            key = (group, identity)
            if begin:
                active[key] = now
            elif key in active:
                duration = (now - active.pop(key)) * 1000
                lane = ('main' if actor == main_tid else 'settings' if actor in tids else
                        'persistent_process_leader' if actor in persistent else 'other')
                waits[group + '_' + lane] += duration
                longest[group + '_' + lane] = max(longest[group + '_' + lane], duration)
                events[group + '_' + lane] += 1
    if transition is not None:
        mark(end, 'end')
    ms = lambda values, scale: {k: round(v * scale, 3) for k, v in sorted(values.items())}
    return {'launch': int(sample), 'total_ms': int(re.search(r'^TotalTime: (\d+)', text, re.M)[1]),
            'retained_events': entries, 'written_events': written, 'trace_window_ms': round((end - start) * 1000, 3),
            'prefs_to_display_ms': round((displayed[-1] - prefs[-1]) * 1000, 3) if prefs and displayed else None,
            'main_thread_observed_ms': ms(totals, 1000), 'events': dict(events),
            'sum_completed_waits_ms': ms(waits, 1), 'max_completed_wait_ms': ms(longest, 1)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    with gzip.open(args.trace, 'rt', errors='replace') as stream:
        header, *parts = re.split(r'^# launch (\d+)\n', stream.read(), flags=re.M)
    rows = [analyze(n, s) for n, s in zip(parts[::2], parts[1::2])]
    if not rows or any(r['retained_events'] != r['written_events'] for r in rows):
        raise SystemExit('empty trace or ring-buffer event loss; do not use launch totals')
    doc = {'kernel': header.strip(), 'clock': 'boot (scheduler events); monotonic (Android log deltas)',
           'notes': 'Time before first observed main-thread switch is excluded. Waits overlap across threads and cannot be summed as a critical path.', 'launches': rows}
    with args.output.open('x', encoding='utf-8') as out:
        json.dump(doc, out, indent=2)
        out.write('\n')


if __name__ == '__main__':
    main()
