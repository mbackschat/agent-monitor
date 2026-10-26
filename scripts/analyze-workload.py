#!/usr/bin/env python3
"""Summarize existing workload captures without sampling processes or modifying inputs."""

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import sys


LIMITATIONS = [
    'Observed CPU excludes unseen workers and CPU after the last successful read; loss percentage is unknown.',
    'CPU is bucketed by the closing executable basename, not by agent/session or verified execution epoch.',
    'Ages are birth-to-observation. Absence from a current-user listing does not prove exit.',
    'Memory is the largest per-scan sum of available footprints, not a sum of process peaks.',
    'Recorder CPU includes sampling and writing; it is not production-monitor overhead.',
    'Files are independent windows; do not sum their lifetime counts or overlapping CPU windows.',
    'Executable lifetime counts can overlap after exec; an unavailable measurement is not zero.',
]
AGE_BINS = [('<=50ms', .05), ('50–500ms', .5), ('500ms–1s', 1), ('1–5s', 5), ('>5s', math.inf)]


def distribution(values):
    ordered = sorted(values)
    def percentile(fraction):
        return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)] if ordered else None
    return dict(count=len(ordered), median=percentile(.5), p90=percentile(.9),
                p99=percentile(.99), maximum=ordered[-1] if ordered else None)


def age_bins(values):
    counts = dict.fromkeys((label for label, _ in AGE_BINS), 0)
    for value in values:
        for label, ceiling in AGE_BINS:
            if value <= ceiling:
                counts[label] += 1
                break
    return counts


def finite(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError('expected a finite number')
    return value


def counter(sample):
    keys = ('rawUserTicks', 'rawSystemTicks', 'numerator', 'denominator', 'sampledAtTicks')
    if any(sample.get(key) is None for key in keys):
        return None
    result = tuple(sample[key] for key in keys)
    if any(type(v) is not int or v < 0 for v in result) or not result[2] or not result[3]:
        raise ValueError('invalid raw counter/timebase')
    return result


class Capture:
    def __init__(self, header):
        if header.get('format') != 'agent-monitor-workload-observations' or header.get('version') != 1:
            raise ValueError('unsupported capture format/version')
        self.header = header
        self.footer = None
        self.scans = 0
        self.first_listing = None
        self.last_listing = None
        self.gaps = []
        self.scan_times = []
        self.populations = []
        self.lives = {}
        self.tools = {}
        self.listed_first = {}
        self.read_pids = set()
        self.listing_available = True
        self.exclusions = Counter()
        self.outcomes = Counter()
        self.outcome_pids = defaultdict(set)

    def add_scan(self, row):
        seq = row['sequence']
        if type(seq) is not int or seq != self.scans:
            raise ValueError('scan sequence must start at zero and remain contiguous')
        listed = finite(row['listedAt'])
        duration = finite(row['scanSeconds'])
        if duration < 0 or (self.last_listing is not None and listed <= self.last_listing):
            raise ValueError('scan times must increase and durations must be nonnegative')
        if self.first_listing is None:
            self.first_listing = listed
        if self.last_listing is not None:
            self.gaps.append(listed - self.last_listing)
        self.last_listing = listed
        self.scan_times.append(duration)
        self.populations.append(len(row['processes']))
        listed_pids = set(row['listedPIDs']) if row.get('listedPIDs') is not None else None
        self.listing_available &= listed_pids is not None
        for pid in listed_pids or ():
            if pid != self.header.get('excludedPID'):
                self.listed_first.setdefault(pid, seq)
        for outcome in row['outcomes']:
            key = (outcome['operation'], outcome['status'], outcome.get('errorNumber'))
            self.outcomes[key] += 1
            self.outcome_pids[key].add(outcome['pid'])
        present = set()
        memory = Counter()
        for sample in row['processes']:
            identity = (sample['identity']['pid'], sample['identity']['startMicroseconds'])
            if any(type(v) is not int for v in identity) or identity in present:
                raise ValueError('invalid or duplicate process identity in scan')
            present.add(identity)
            self.read_pids.add(identity[0])
            image = sample.get('executable') or sample['name']
            name = Path(image).name
            at = finite(sample['sampledAt'])
            birth = sample.get('startedAt')
            if birth is not None:
                birth = finite(birth)
                if birth > at:
                    raise ValueError('process birth is later than its observation')
            if identity not in self.lives:
                self.lives[identity] = dict(birth=birth, last_seq=seq, absent_at=None, counter=None,
                                            counter_name=None, last_at=at)
            life = self.lives[identity]
            if life['birth'] is None:
                life['birth'] = birth
            life.update(last_seq=seq, absent_at=None, last_at=at)
            tool = self.tools.setdefault(name, dict(cpu=0., contributions=0, initial=0., transition=0., cohorts={},
                                                    peak_memory=None, missing_memory=0))
            cohort = tool['cohorts'].setdefault(identity, dict(reads=0, last=at, fallback_reads=0))
            cohort['reads'] += 1
            cohort['last'] = at
            if not sample.get('executable'):
                cohort['fallback_reads'] += 1
            footprint = sample.get('footprintBytes')
            if footprint is None:
                tool['missing_memory'] += 1
            else:
                if finite(footprint) < 0:
                    raise ValueError('negative footprint')
                memory[name] += footprint
            self.add_counter(sample, life, tool, image, seq)
        for name, value in memory.items():
            self.tools[name]['peak_memory'] = max(self.tools[name]['peak_memory'] or 0, value)
        if listed_pids is not None:
            for identity, life in self.lives.items():
                if identity not in present and identity[0] not in listed_pids and life['absent_at'] is None:
                    # Enumeration spans the scan; its end is conservative, unlike the pre-listing anchor.
                    life['absent_at'] = listed + duration
        self.scans += 1

    def add_counter(self, sample, life, tool, image, seq):
        current = counter(sample)
        if current is None:
            self.exclusions['missing'] += 1
            return
        prior = life['counter']
        delta = 0.
        if prior is not None:
            if current[4] <= prior[4]:
                self.exclusions['invalid_time'] += 1
                return
            if current[2:4] == prior[2:4] and current[0] >= prior[0] and current[1] >= prior[1]:
                delta = ((current[0] - prior[0]) + (current[1] - prior[1])) * current[2] / current[3] / 1e9
                tool['contributions'] += 1
                if life['counter_name'] != image:
                    tool['transition'] += delta
            else:
                self.exclusions['discontinuity'] += 1
        elif seq > 0 and life['birth'] is not None and life['birth'] > self.first_listing:
            delta = (current[0] + current[1]) * current[2] / current[3] / 1e9
            tool['contributions'] += 1
            tool['initial'] += delta
        tool['cpu'] += delta
        life['counter'] = current
        life['counter_name'] = image

    def result(self):
        warnings = []
        if self.footer is None:
            warnings.append('Missing footer: capture completion and recorder cost are unknown.')
        elif self.footer['reason'] != 'duration':
            warnings.append('Capture stopped with reason: ' + self.footer['reason'])
        if not self.listing_available:
            warnings.append('Some scans lack PID listings; listing-absence statistics are partial.')
        if self.exclusions:
            warnings.append('Counter exclusions exist; inspect counter_exclusions before comparing CPU.')
        contributors = []
        for name, tool in self.tools.items():
            born = [(self.lives[i], c) for i, c in tool['cohorts'].items()
                    if self.lives[i]['birth'] is not None and self.lives[i]['birth'] > self.first_listing]
            ages = [c['last'] - life['birth'] for life, c in born]
            absence_ages = [life['absent_at'] - life['birth'] for life, _ in born if life['absent_at'] is not None]
            contributors.append(dict(
                name=name, lifetimes=len(tool['cohorts']), newborn_lifetimes=len(born),
                fallback_name_reads=sum(c['fallback_reads'] for c in tool['cohorts'].values()),
                fallback_name_lifetimes=sum(c['fallback_reads'] > 0 for c in tool['cohorts'].values()),
                observed_cpu_seconds=tool['cpu'] if tool['contributions'] else None,
                accepted_cpu_contributions=tool['contributions'], newborn_initial_cpu_seconds=tool['initial'],
                image_transition_cpu_seconds=tool['transition'], max_scan_footprint_bytes=tool['peak_memory'],
                missing_footprint_reads=tool['missing_memory'],
                newborn_single_image_read=sum(c['reads'] == 1 for _, c in born),
                newborn_image_read_counts=distribution([c['reads'] for _, c in born]),
                newborn_last_image_age_seconds=distribution(ages), newborn_last_image_age_bins=age_bins(ages),
                newborn_lifetime_unobserved_final=sum(life['last_seq'] < self.scans - 1 for life, _ in born),
                newborn_absent_listing_age_seconds=distribution(absence_ages),
                newborn_absent_listing_age_bins=age_bins(absence_ages)))
        contributors.sort(key=lambda c: (-(c['observed_cpu_seconds'] or 0), c['name']))
        unread = [seq for pid, seq in self.listed_first.items() if pid not in self.read_pids]
        return dict(
            header={k: self.header[k] for k in ('startedAt', 'os', 'intervalSeconds', 'durationSeconds', 'maximumBytes') if k in self.header},
            footer=self.footer, scans=self.scans, observed_window_seconds=(self.last_listing - self.first_listing) if self.scans else None,
            listing_gap_seconds=distribution(self.gaps), scan_seconds=distribution(self.scan_times),
            readable_population=dict(minimum=min(self.populations, default=0), maximum=max(self.populations, default=0)),
            unique_lifetimes=len(self.lives), counter_exclusions=dict(self.exclusions),
            listed_unread_pid_values=dict(baseline=unread.count(0), first_listed_later=sum(seq > 0 for seq in unread)),
            outcomes=[dict(operation=k[0], status=k[1], errno=k[2], events=count, pid_values=len(self.outcome_pids[k]))
                      for k, count in sorted(self.outcomes.items(), key=lambda item: str(item[0]))],
            contributors=contributors, warnings=warnings, limitations=LIMITATIONS)


def reject_constant(value):
    raise ValueError('non-finite JSON number: ' + value)


def analyze(stream):
    capture = None
    for line_number, line in enumerate(stream, 1):
        try:
            row = json.loads(line, parse_constant=reject_constant)
            if capture is None:
                if row['kind'] != 'header':
                    raise ValueError('first record must be a header')
                capture = Capture(row)
            elif capture.footer is not None:
                raise ValueError('record after footer')
            elif row['kind'] == 'scan':
                capture.add_scan(row)
            elif row['kind'] == 'footer':
                if row['scanCount'] != capture.scans:
                    raise ValueError('footer scan count does not match records')
                capture.footer = {k: row[k] for k in ('reason', 'scanCount', 'elapsedSeconds', 'processCPUSeconds')}
                for key in ('elapsedSeconds', 'processCPUSeconds'):
                    if finite(capture.footer[key]) < 0:
                        raise ValueError('negative footer measurement')
            else:
                raise ValueError('unexpected record kind')
        except (ValueError, KeyError, TypeError, AttributeError) as error:
            raise ValueError(f'line {line_number}: {error}') from error
    if capture is None:
        raise ValueError('empty capture')
    return capture.result()


def text_report(report, top):
    footer = report['footer']
    duration = f"{footer['elapsedSeconds']:.3f}s / {footer['reason']}" if footer else 'incomplete (no footer)'
    lines = [f"{report['file']}: {report['scans']} scans, {duration}"]
    gap = report['listing_gap_seconds']
    if gap['count']:
        lines.append(f"Listing gap: median {gap['median'] * 1000:.1f}ms, p99 {gap['p99'] * 1000:.1f}ms, max {gap['maximum'] * 1000:.1f}ms")
    if footer and footer['elapsedSeconds'] > 0:
        percent = footer['processCPUSeconds'] / footer['elapsedSeconds'] * 100
        lines.append(f"Recorder CPU: {footer['processCPUSeconds']:.3f}s ({percent:.2f}% of one core)")
    population = report['readable_population']
    lines.append(f"Readable population: {population['minimum']}–{population['maximum']}; exact lifetimes: {report['unique_lifetimes']}")
    lines += ['Executable                         CPU s   Scan MiB   Lives   Newborn',
              '-------------------------------- -------- ---------- ------- --------']
    for c in report['contributors'][:top]:
        # Escape control characters from executable labels before terminal output.
        name = json.dumps(c['name'], ensure_ascii=True)[1:-1]
        memory = c['max_scan_footprint_bytes']
        memory_label = f'{memory / 1048576:.1f}' if memory is not None else 'unknown'
        cpu = c['observed_cpu_seconds']
        cpu_label = f'{cpu:.3f}' if cpu is not None else 'unknown'
        lines.append(f"{name:32} {cpu_label:>8} {memory_label:>10} {c['lifetimes']:7} {c['newborn_lifetimes']:8}")
        if c['newborn_lifetimes']:
            bins = ', '.join(f'{key}: {count}' for key, count in c['newborn_last_image_age_bins'].items())
            lines.append(f"  Newborn last-image ages: {bins}; single-read: {c['newborn_single_image_read']}")
        if c['image_transition_cpu_seconds']:
            lines.append(f"  CPU across a changed executable label: {c['image_transition_cpu_seconds']:.3f}s")
        if c['fallback_name_reads']:
            lines.append(f"  Kernel-name fallback: {c['fallback_name_lifetimes']} lifetimes, {c['fallback_name_reads']} reads")
    unread = report['listed_unread_pid_values']
    lines.append(f"Listed but never read PID values: {unread['baseline']} baseline, {unread['first_listed_later']} first listed later (class unknown)")
    for outcome in report['outcomes']:
        lines.append(f"Native outcome: {outcome['operation']} / {outcome['status']} / errno {outcome['errno']}: {outcome['events']} events, {outcome['pid_values']} PID values")
    lines.extend('Warning: ' + w for w in report['warnings'])
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path, help='existing JSONL captures; never modified')
    parser.add_argument('--json', action='store_true', help='emit full per-file reports as JSON to stdout')
    parser.add_argument('--top', type=int, default=10, help='contributors shown per text report (default: 10)')
    args = parser.parse_args()
    if args.top <= 0:
        parser.error('--top must be positive')
    reports = []
    for path in args.files:
        try:
            with path.open() as stream:
                report = analyze(stream)
            report['file'] = path.name
            reports.append(report)
        except (OSError, UnicodeError, ValueError) as error:
            parser.exit(1, f'{path.name}: {error}\n')
    if args.json:
        print(json.dumps(reports, indent=2, allow_nan=False))
    else:
        print('\n\n'.join(text_report(r, args.top) for r in reports))
        print('\nInterpretation:\n' + '\n'.join('- ' + line for line in LIMITATIONS))


if __name__ == '__main__':
    main()
