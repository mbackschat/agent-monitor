"""Compile and test offline by default; native calibration requires explicit authorization."""
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'calibration.swift'
MAX_LINE_BYTES = 1_048_576
MAX_RUN_BYTES = 8_388_608
BATCHES = ['a1', 'b1', 'a2', 'bprime', 'a3', 'c1']
EVENTS = ['before_device', 'after_device', 'before_queue_a_creation', 'after_queue_a_before_work']
EVENTS += [f'{phase}_a1' for phase in ['before', 'first', 'after']]
EVENTS += ['before_queue_b_creation', 'after_queue_b_before_work']
EVENTS += [f'{phase}_{batch}' for batch in ['b1', 'a2'] for phase in ['before', 'first', 'after']]
EVENTS += ['after_b_release', 'before_queue_bprime_creation', 'after_queue_bprime_before_work']
EVENTS += [f'{phase}_{batch}' for batch in ['bprime', 'a3'] for phase in ['before', 'first', 'after']]
EVENTS += ['after_bprime_release', 'before_queue_c_creation', 'after_queue_c_before_work']
EVENTS += [f'{phase}_c1' for phase in ['before', 'first', 'after']]
EVENTS += ['before_cooldown', 'after_cooldown']
DELAYED = {'after_device', 'after_queue_a_before_work', 'after_queue_b_before_work',
           'after_queue_bprime_before_work', 'after_queue_c_before_work',
           'after_b_release', 'after_bprime_release', 'after_cooldown'}
DELAYED.update(f'after_{batch}' for batch in BATCHES)


def ensure(condition, reason):
    if not condition:
        raise RuntimeError(reason)


def authorized_mode(arguments):
    if arguments == []:
        return False
    if arguments == ['--authorized-calibration']:
        return True
    raise ValueError('default is offline preflight; native work needs --authorized-calibration and user authorization')


class Reader:
    def __init__(self, process, budget):
        self.process, self.budget = process, budget
        self.buffer = bytearray()

    def line(self, deadline):
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            while b'\n' not in self.buffer:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise TimeoutError('owned probe deadline')
                block = os.read(self.process.stdout.fileno(), 65536)
                if not block:
                    raise RuntimeError('probe closed output before acknowledgement')
                self.buffer.extend(block)
                self.budget[0] += len(block)
                ensure(self.budget[0] <= MAX_RUN_BYTES, 'run output cap')
                ensure(len(self.buffer) <= MAX_LINE_BYTES + 1, 'line output cap')
        line, _, tail = self.buffer.partition(b'\n')
        self.buffer = bytearray(tail)
        ensure(len(line) <= MAX_LINE_BYTES, 'line output cap')
        return json.loads(line)


def send(process, text):
    process.stdin.write((text + '\n').encode())
    process.stdin.flush()


def offsets(label):
    return [0, 0.05, 0.2] if label in DELAYED else [0]


def reference_intent(label):
    position = EVENTS.index(label)
    held, released = [], []
    for name, created, retired in [
        ('A', 'after_queue_a_before_work', None),
        ('B', 'after_queue_b_before_work', 'after_b_release'),
        ('Bprime', 'after_queue_bprime_before_work', 'after_bprime_release'),
        ('C', 'after_queue_c_before_work', None),
    ]:
        if position >= EVENTS.index(created):
            if retired is not None and position >= EVENTS.index(retired):
                released.append(name)
            else:
                held.append(name)
    return {'intendedHeldApplicationQueues': held, 'releasedApplicationQueues': released,
            'driverDestructionAsserted': False}


def run_authorized(binary, *, authorized):
    ensure(authorized, 'native execution is not authorized')
    ensure(os.getuid() != 0 and os.geteuid() != 0, 'requires ordinary user')
    environment = dict(os.environ, AGENT_MONITOR_GPU_CALIBRATION='explicit')
    observer = worker = timer = None
    observations, events, budget = [], [], [0]
    began = time.monotonic()
    deadline = began + 20
    expired = threading.Event()
    try:
        observer = subprocess.Popen([str(binary), '--authorized-observer'], stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, env=environment)
        worker = subprocess.Popen([str(binary), '--authorized-worker'], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, env=environment)

        def stop_worker():
            expired.set()
            # The parent retains this owned child; no lookup or signal uses a sampled process ID.
            if worker.poll() is None:
                worker.kill()

        timer = threading.Timer(max(0, deadline - time.monotonic()), stop_worker)
        timer.start()
        observed, worked = Reader(observer, budget), Reader(worker, budget)
        send(observer, str(worker.pid))
        ensure(observed.line(deadline) == {'ready': True}, 'observer readiness')
        for expected in EVENTS:
            event = worked.line(deadline)
            ensure(event.get('label') == expected, 'unexpected worker checkpoint')
            event['applicationReferenceIntent'] = reference_intent(expected)
            events.append(event)
            anchor = time.monotonic()
            for delay in offsets(expected):
                wait = anchor + delay - time.monotonic()
                if wait > 0:
                    time.sleep(wait)
                ensure(time.monotonic() < deadline, 'observation deadline')
                ensure(len(observations) < 64, 'observation cap')
                label = f'{expected}@{round(delay * 1000)}ms'
                send(observer, label)
                observation = observed.line(deadline)
                ensure(observation.get('label') == label, 'unexpected observation label')
                observation['applicationReferenceIntent'] = reference_intent(expected)
                observations.append(observation)
            send(worker, 'continue')
        ensure(worker.wait(timeout=max(0.001, deadline-time.monotonic())) == 0, 'worker failed')
        timer.cancel()
        ensure(not expired.is_set(), 'watchdog triggered')
        send(observer, 'quit')
        ensure(observer.wait(timeout=2) == 0, 'observer failed')
        batches = [event for event in events if 'submissions' in event]
        ensure([event['label'] for event in batches] == [f'after_{name}' for name in BATCHES], 'batch order')
        ensure(all(event['submissions'] == 64 and event['outputsVerified'] for event in batches), 'batch verification')
        ensure(sum(event['submissions'] for event in batches) <= 384, 'submission cap')
        return {
            'completedUTC': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'workerAndObservationWallSeconds': time.monotonic()-began,
            'watchdogSeconds': 20, 'watchdogTriggered': False, 'nativeExecuted': True,
            'events': events, 'observations': observations,
            'selectedEndpointReplays': [
                {'start': 'after_b1@200ms', 'end': 'after_b_release@200ms',
                 'question': 'surviving A gain with B retirement'},
                {'start': 'after_bprime@200ms', 'end': 'after_c1@200ms',
                 'question': 'Bprime retirement and C creation while A advances; equal record count is to be observed, not assumed'},
            ],
            'limits': [
                'Endpoint replays omit retained intermediate checkpoints; this is not an independent polling census.',
                'Client ordinals identify registry objects within this run; record arrayIndex is order, not stable identity.',
                'Only creator-associated owned-worker clients in the IOService plane are inventoried; exclusive ownership is unproved.',
                'Missing fields/timings/task measurements are unavailable, never measured idle.',
                'Numeric values preserve their observed encodings; units and charging meanings are not assumed equal.',
                'Task query is worker-self only; no task port for another process is requested.',
                'Explicit data-buffer size does not bound compiler/framework/registry allocations.',
                'The watchdog cannot cancel already-submitted GPU work or establish native reader preemption.',
                'Host callback time includes handler scheduling; wait-return time is separate.',
            ],
        }
    finally:
        if timer:
            timer.cancel()
            timer.join()
        for process in [worker, observer]:
            if process is not None:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=2)
                process.stdin.close()
                process.stdout.close()


def offline_checks():
    ensure(not authorized_mode([]), 'unsafe default')
    ensure(authorized_mode(['--authorized-calibration']), 'explicit mode parsing')
    try:
        authorized_mode(['--worker'])
    except ValueError:
        pass
    else:
        raise RuntimeError('unsupported mode accepted')
    try:
        run_authorized(Path('/never-launched'), authorized=False)
    except RuntimeError as error:
        ensure(str(error) == 'native execution is not authorized', 'authorization rejected too late')
    else:
        raise RuntimeError('native execution bypass')
    ensure(len(EVENTS) == 32 and len(set(EVENTS)) == 32, 'event sequence')
    ensure(sum(len(offsets(label)) for label in EVENTS) == 60, 'observation schedule')
    ensure(len(BATCHES)*64 == 384, 'command schedule')
    ensure(EVENTS.index('after_bprime') < EVENTS.index('before_a3') < EVENTS.index('after_bprime_release')
           < EVENTS.index('after_queue_c_before_work') < EVENTS.index('before_c1'), 'replacement order')
    ensure(EVENTS.index('after_b1') < EVENTS.index('before_a2') < EVENTS.index('after_b_release'), 'retirement order')
    ensure(reference_intent('after_a2')['intendedHeldApplicationQueues'] == ['A', 'B'], 'B retention intent')
    ensure(reference_intent('after_a3')['intendedHeldApplicationQueues'] == ['A', 'Bprime'], 'Bprime retention intent')
    ensure(reference_intent('after_cooldown')['intendedHeldApplicationQueues'] == ['A', 'C'], 'cooldown retention intent')
    ensure(4096*4 <= 65536, 'explicit data allocation')
    return {'pythonOfflineChecks': 'passed', 'workerCheckpoints': len(EVENTS),
            'plannedRegistryObservations': 60, 'maximumSubmissions': 384, 'nativeExecuted': False}


def main():
    authorized = authorized_mode(sys.argv[1:])
    checks = offline_checks()
    scratch = Path(os.environ['AGENT_MONITOR_SCRATCH'])
    binary = scratch/'calibration'
    with (scratch/'compile.log').open('w') as log:
        compilation = subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '6',
                                     '-module-cache-path', str(Path.cwd()/'.build/module-cache'),
                                     str(SOURCE), '-o', str(binary)], stdout=log, stderr=subprocess.STDOUT, timeout=120)
    if compilation.returncode:
        raise RuntimeError((scratch/'compile.log').read_text()[-16000:])
    preflight = subprocess.run([str(binary), '--self-test'], capture_output=True, text=True, timeout=5)
    ensure(preflight.returncode == 0, preflight.stdout+preflight.stderr)
    checks['swiftOfflineChecks'] = json.loads(preflight.stdout)
    checks['sourceSHA256'] = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    checks['supervisorSHA256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    checks['compiler'] = subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True, stderr=subprocess.STDOUT).strip()
    checks['sdk'] = subprocess.check_output(['xcrun', '--show-sdk-version'], text=True).strip()
    (ROOT/'preflight.json').write_text(json.dumps(checks, indent=2, sort_keys=True)+'\n')
    print(json.dumps(checks, sort_keys=True), flush=True)
    if authorized:
        result = run_authorized(binary, authorized=True)
        result['sourceSHA256'] = checks['sourceSHA256']
        result['supervisorSHA256'] = checks['supervisorSHA256']
        (ROOT/'result.json').write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
        print(json.dumps({'completed': True, 'observations': len(result['observations'])}), flush=True)


if __name__ == '__main__':
    main()
