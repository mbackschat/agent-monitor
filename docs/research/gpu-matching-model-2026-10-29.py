"""Offline dated experiment for a conditional GPU counter model; never reads native state."""
from dataclasses import dataclass
from enum import Enum
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import platform

MAX_RECORDS = 128
UINT64_MAX = (1 << 64) - 1
DOMAIN = (1, 2, 3, 4)


class Invalid(ValueError):
    pass


class Status(str, Enum):
    BASELINE = 'baseline'
    LOWER_BOUND = 'conditional_lower_bound'
    UNAVAILABLE = 'unavailable'


def checked_add(left, right):
    total = left + right
    if total > UINT64_MAX:
        raise Invalid('overflow')
    return total


def values(raw):
    if not isinstance(raw, (list, tuple)):
        raise Invalid('missing_or_invalid_records')
    if len(raw) > MAX_RECORDS:
        raise Invalid('record_capacity')
    total = 0
    for value in raw:
        if type(value) is not int or not 0 <= value <= UINT64_MAX:
            raise Invalid('invalid_counter')
        total = checked_add(total, value)
    return tuple(raw), total


@dataclass(frozen=True)
class Match:
    lower_bound: int
    scan_steps: int


def minimum_increment(before, after):
    old, _ = values(before)
    new, total = values(after)
    old = sorted(old, reverse=True)
    new = sorted(new, reverse=True)
    previous = current = matched = steps = 0
    while previous < len(old) and current < len(new):
        steps += 1
        if old[previous] <= new[current]:
            matched = checked_add(matched, old[previous])
            current += 1
        previous += 1
    return Match(total - matched, steps)


def exhaustive_oracle(before, after):
    def visit(index, used):
        if index == len(after):
            return 0
        current = after[index]
        candidates = [current + visit(index + 1, used)]
        for previous, amount in enumerate(before):
            if previous not in used and amount <= current:
                candidates.append(current - amount + visit(index + 1, used | {previous}))
        return min(candidates)
    return visit(0, frozenset())


@dataclass(frozen=True)
class Result:
    status: Status
    reason: str
    increment: int | None = None


class Ledger:
    """Retain credits for adjacent reads in one synthetic verified domain.

    The fixture domain represents client, exact process lifetime, accounting owner
    and units. This offline model cannot establish any of those native identities.
    """
    def __init__(self, domain=DOMAIN):
        self.domain = domain
        self.baseline = None
        self.epoch = None
        self.watermark = -1
        self.total = 0

    def reject(self, reason):
        self.baseline = None
        self.epoch = None
        return Result(Status.UNAVAILABLE, reason)

    def read(self, sequence, records, *, domain=DOMAIN, schema=1, epoch=0,
             supported_history=True, valid=True):
        if type(sequence) is not int or not 0 <= sequence <= UINT64_MAX or sequence <= self.watermark:
            return self.reject('unordered_or_duplicate_read')
        previous_sequence = self.watermark
        self.watermark = sequence
        if previous_sequence >= 0 and sequence != previous_sequence + 1:
            return self.reject('missing_sequence')
        if not valid:
            return self.reject('observation_gap')
        if domain != self.domain:
            return self.reject('domain_changed')
        if type(schema) is not int or schema != 1:
            return self.reject('unsupported_schema')
        if type(epoch) is not int or not 0 <= epoch <= UINT64_MAX:
            return self.reject('invalid_epoch')
        if not supported_history:
            return self.reject('history_contract_unestablished')
        try:
            current, _ = values(records)
            if self.baseline is None or self.epoch != epoch:
                self.baseline, self.epoch = current, epoch
                return Result(Status.BASELINE, 'first_read_or_known_reset')
            bound = minimum_increment(self.baseline, current).lower_bound
            total = checked_add(self.total, bound)
        except Invalid as error:
            return self.reject(str(error))
        self.baseline, self.epoch, self.total = current, epoch, total
        return Result(Status.LOWER_BOUND, 'unseen_work_unbounded', bound)


def check(condition, label):
    if not condition:
        raise AssertionError(label)


def smoke():
    expected = [
        ('survivor_despite_retirement', [10, 100], [20], 10),
        ('permutation', [10, 100], [110, 20], 20),
        ('newborn_visible', [], [7], 7),
        ('all_retired', [10], [], 0),
        ('ambiguous_replacement', [10, 20], [30, 40], 40),
        ('equal_values_are_distinct', [5, 5], [6, 6], 2),
        ('greater_before_cannot_match', [100], [50], 50),
        ('uint64_edge', [UINT64_MAX - 1], [UINT64_MAX], 1),
    ]
    for label, before, after, wanted in expected:
        got = minimum_increment(before, after)
        check(got.lower_bound == wanted, f'{label}: expected {wanted}, got {got.lower_bound}')
        check(got.scan_steps <= len(before), label + ': scan bound')
        check(exhaustive_oracle(before, after) == wanted, label + ': independent oracle')
    return len(expected)


def enumeration_checks():
    multisets = [x for n in range(5) for x in itertools.combinations_with_replacement(range(5), n)]
    compared = 0
    for before in multisets:
        for after in multisets:
            result = minimum_increment(before, after)
            check(result.lower_bound == exhaustive_oracle(before, after), 'matching oracle disagreement')
            check(result.scan_steps <= len(before), 'linear scan bound')
            compared += 1
    ordered = [x for n in range(4) for x in itertools.product(range(3), repeat=n)]
    permutations = 0
    for before in ordered:
        for after in ordered:
            check(minimum_increment(before, after).lower_bound == exhaustive_oracle(before, after),
                  'order/duplicate oracle disagreement')
            permutations += 1
    histories = 0
    births = [x for n in range(3) for x in itertools.product(range(3), repeat=n)]
    for before in ordered:
        for events in itertools.product(range(6), repeat=len(before)):
            # Events 0..2 survive with that gain; 3..5 retire with a tail of event-3.
            survivors = [value + event for value, event in zip(before, events) if event < 3]
            actual_old = sum(event if event < 3 else event - 3 for event in events)
            for newborns in births:
                after = survivors + list(newborns)
                actual = actual_old + sum(newborns)
                check(minimum_increment(before, after).lower_bound <= actual, 'hidden-history overcount')
                histories += 1
    return {'multisetPairs': compared, 'orderedPairs': permutations, 'hiddenOneIntervalHistories': histories}


def multi_step_checks():
    leaves, transitions = 0, 0
    def visit(state, depth, credited, actual):
        nonlocal leaves, transitions
        if depth == 0:
            check(credited <= actual, 'multi-step overcount')
            leaves += 1
            return
        options = []
        for amount in state:
            if amount is None:
                options.append([(None, 0), (0, 0), (1, 1), (2, 2)])
            else:
                options.append([(amount, 0), (amount + 1, 1), (None, 0), (None, 1)])
        for outcomes in itertools.product(*options):
            next_state = tuple(value for value, _ in outcomes)
            increment = minimum_increment([x for x in state if x is not None],
                                          [x for x in next_state if x is not None]).lower_bound
            work = sum(delta for _, delta in outcomes)
            check(increment <= work, 'multi-step interval overcount')
            transitions += 1
            visit(next_state, depth - 1, credited + increment, actual + work)
    for initial in [(None, None), (0, 1)]:
        visit(initial, 3, 0, 0)
    return {'threeIntervalHistories': leaves, 'threeIntervalTransitions': transitions}


def state_checks():
    checks = 0
    def expect(condition, label):
        nonlocal checks
        check(condition, label)
        checks += 1
    ledger = Ledger()
    expect(ledger.read(1, [100]).status == Status.BASELINE and ledger.total == 0, 'no initial backfill')
    expect(ledger.read(2, [110]).increment == 10, 'first increment')
    expect(ledger.read(3, [110]).increment == 0 and ledger.total == 10, 'repeat values do not double-credit')
    expect(ledger.read(4, []).increment == 0 and ledger.total == 10, 'valid empty preserves credit')
    expect(ledger.read(5, [5]).increment == 5 and ledger.total == 15, 'closed-history newborn')
    rejected = ledger.read(6, None)
    expect(rejected.status == Status.UNAVAILABLE and rejected.increment is None, 'missing is not empty')
    expect(ledger.read(7, [1000]).status == Status.BASELINE and ledger.total == 15, 'no bridge over missing')
    expect(ledger.read(8, [1003]).increment == 3 and ledger.total == 18, 'resume after baseline')
    failures = [
        ({'valid': False}, 'observation_gap'),
        ({'domain': (1, 99, 3, 4)}, 'domain_changed'),
        ({'domain': (1, 2, 99, 4)}, 'domain_changed'),
        ({'domain': (1, 2, 3, 99)}, 'domain_changed'),
        ({'schema': 2}, 'unsupported_schema'),
        ({'supported_history': False}, 'history_contract_unestablished'),
        ({'epoch': -1}, 'invalid_epoch'),
    ]
    for kwargs, reason in failures:
        item = Ledger()
        item.read(1, [10])
        item.read(2, [20])
        outcome = item.read(3, [30], **kwargs)
        expect(outcome.status == Status.UNAVAILABLE and outcome.reason == reason and item.total == 10,
               'failure preserves accepted ledger: ' + reason)
        expect(item.read(4, [100]).status == Status.BASELINE and item.total == 10,
               'failure invalidates baseline: ' + reason)
        expect(item.read(5, [105]).increment == 5 and item.total == 15, 'failure recovery: ' + reason)
    invalid_records = [None, {}, [True], [-1], [1.5], [float('nan')], [UINT64_MAX + 1],
                       [UINT64_MAX, 1], [0] * (MAX_RECORDS + 1)]
    for raw in invalid_records:
        item = Ledger()
        item.read(1, [0])
        item.read(2, [2])
        outcome = item.read(3, raw)
        expect(outcome.status == Status.UNAVAILABLE and outcome.increment is None and item.total == 2,
               'invalid input excluded')
        expect(item.read(4, [50]).status == Status.BASELINE and item.total == 2, 'invalid input no bridge')
    item = Ledger()
    item.read(1, [10])
    item.read(2, [20])
    expect(item.read(3, [0], epoch=1).status == Status.BASELINE and item.total == 10, 'known reset baseline')
    expect(item.read(4, [3], epoch=1).increment == 3 and item.total == 13, 'known reset recovery')
    expect(item.read(4, [99], epoch=1).status == Status.UNAVAILABLE, 'duplicate sequence rejected')
    expect(item.read(5, [100], epoch=1).status == Status.BASELINE and item.total == 13, 'duplicate no bridge')
    expect(item.read(2, [101], epoch=1).status == Status.UNAVAILABLE, 'backward sequence rejected')
    item = Ledger()
    item.read(1, [10])
    item.read(2, [20])
    expect(item.read(4, [30]).status == Status.UNAVAILABLE and item.total == 10, 'missing sequence excludes')
    expect(item.read(5, [100]).status == Status.BASELINE and item.total == 10, 'missing sequence no bridge')
    expect(item.read(6, [105]).increment == 5 and item.total == 15, 'missing sequence recovery')
    item = Ledger()
    item.read(1, [0])
    expect(item.read(2, [UINT64_MAX]).increment == UINT64_MAX, 'ledger reaches max')
    item.read(3, [])
    expect(item.read(4, [1]).status == Status.UNAVAILABLE and item.total == UINT64_MAX, 'ledger overflow excludes')
    expect(item.read(5, [2]).status == Status.BASELINE and item.total == UINT64_MAX, 'overflow no bridge')
    a, b = Ledger(), Ledger(domain=(9, 2, 3, 4))
    a.read(1, [10]); b.read(1, [100], domain=b.domain)
    a.read(2, [20]); b.read(2, [150], domain=b.domain)
    a.read(3, [30])
    departed = b.read(3, None, domain=b.domain, valid=False)
    expect(departed.status == Status.UNAVAILABLE and a.total + b.total == 70,
           'client departure cannot cancel another client')
    expect(b.read(4, [170], domain=b.domain).status == Status.BASELINE and a.total + b.total == 70,
           'client reappearance cannot backfill old history')
    expect(b.read(5, [175], domain=b.domain).increment == 5 and a.total + b.total == 75,
           'client reappearance resumes from fresh baseline')
    expect(len(a.baseline) <= MAX_RECORDS and len(b.baseline) <= MAX_RECORDS, 'bounded baseline state')
    capacity = minimum_increment([1] * MAX_RECORDS, [2] * MAX_RECORDS)
    expect(capacity.lower_bound == MAX_RECORDS and capacity.scan_steps <= MAX_RECORDS, 'maximum accepted size')
    return checks


def negative_controls():
    # These deliberately incorrect alternatives must disagree with independent known histories.
    cases = [
        {'case': 'positional_clamp', 'wrong': sum(max(0, b-a) for a, b in zip([10,100], [110,20])), 'true': 20},
        {'case': 'aggregate_clamp', 'wrong': max(0, sum([20])-sum([10,100])), 'true': 10},
        {'case': 'imported_history', 'wrong': minimum_increment([10], [100]).lower_bound, 'true': 0},
        {'case': 'merged_old_history', 'wrong': minimum_increment([10,20], [40]).lower_bound, 'true': 10},
        {'case': 'split_old_history', 'wrong': minimum_increment([100], [50,60]).lower_bound, 'true': 10},
        {'case': 'undetected_reset_to_nonzero', 'wrong': minimum_increment([10], [20]).lower_bound, 'true': 0},
    ]
    for case in cases:
        check(case['wrong'] != case['true'], 'negative control ineffective: ' + case['case'])
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = {'smokeCases': smoke()}
    if not args.smoke:
        result.update(enumeration_checks())
        result.update(multi_step_checks())
        result['stateAssertions'] = state_checks()
        result['negativeControls'] = negative_controls()
    result.update({'sourceSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   'python': platform.python_version(), 'recordCap': MAX_RECORDS,
                   'counterAndLedgerMaximum': UINT64_MAX, 'nativeCalls': False,
                   'model': 'closed visible history; true births start at zero; monotone distinct additive sources',
                   'claim': 'conditional minimum visible contribution, never completeness or idle',
                   'unrestrictedVisibility': 'trivial zero bound only; ledger returns unavailable',
                   'status': 'passed'})
    encoded = json.dumps(result, indent=2, sort_keys=True) + '\n'
    if args.output:
        args.output.write_text(encoded)
    print(encoded, end='')


if __name__ == '__main__':
    main()
