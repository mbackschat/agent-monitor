"""Dated, explicitly authorized calibration; default invocation never generates GPU work."""
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
SCRATCH = Path(os.environ['AGENT_MONITOR_SCRATCH'])


def line_from(process, deadline):
    data = bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while len(data) < 65536:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise TimeoutError('owned probe deadline')
            byte = os.read(process.stdout.fileno(), 1)
            if not byte:
                raise RuntimeError('probe closed output before acknowledgement')
            if byte == b'\n':
                return json.loads(data)
            data.extend(byte)
    raise RuntimeError('probe line bound exceeded')


def send(process, text):
    process.stdin.write((text + '\n').encode())
    process.stdin.flush()


def run(binary):
    observer = subprocess.Popen([str(binary), 'observer'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    worker = None
    timer = None
    observations, events = [], []
    began = time.monotonic()
    deadline = began + 20
    expired = threading.Event()
    try:
        worker = subprocess.Popen([str(binary), 'worker'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

        def stop_worker():
            expired.set()
            # Popen retains/reaps this child; no lookup or signal by a sampled PID.
            if worker.poll() is None:
                worker.kill()

        timer = threading.Timer(max(0, deadline - time.monotonic()), stop_worker)
        timer.start()
        send(observer, str(worker.pid))
        assert line_from(observer, deadline) == {'ready': True}
        while len(events) < 32:
            event = line_from(worker, deadline)
            events.append(event)
            label = event['label']
            offsets = [0, 0.05, 0.2] if label.startswith('after_') or label == 'b_application_references_released' else [0]
            anchor = time.monotonic()
            for delay in offsets:
                wait = anchor + delay - time.monotonic()
                if wait > 0:
                    time.sleep(wait)
                if time.monotonic() >= deadline:
                    raise TimeoutError('observation deadline')
                send(observer, f'{label}@{round(delay * 1000)}ms')
                observations.append(line_from(observer, deadline))
            send(worker, 'continue')
            if label == 'after_cooldown':
                break
        else:
            raise RuntimeError('event bound exceeded')
        assert worker.wait(timeout=max(0.001, deadline - time.monotonic())) == 0
        timer.cancel()
        assert not expired.is_set()
        send(observer, 'quit')
        assert observer.wait(timeout=2) == 0
        batches = [event for event in events if 'submissions' in event]
        assert len(batches) == 3
        assert sum(event['submissions'] for event in batches) <= 384
        assert all(event['outputsVerified'] for event in batches)
        return {
            'completedUTC': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'workerAndObservationWallSeconds': time.monotonic() - began,
            'watchdogSeconds': 20, 'watchdogTriggered': expired.is_set(),
            'unprivileged': os.getuid() != 0 and os.geteuid() != 0,
            'events': events, 'observations': observations,
            'limits': [
                'Only the disposable worker is associated with counters; creator strings are not general ownership proof.',
                'Aggregate raw counters have no established unit or capacity denominator.',
                'No raw process birth, PID, registry identity or individual record is emitted.',
                'Batch wall time includes the first-command observation pause.',
                'B application references were released; driver destruction was not forced.',
                'One run is not sustained cost, exit coverage, overlapping-work or cross-version acceptance.',
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


def main():
    if sys.argv[1:] not in [[], ['--authorized-calibration']]:
        raise SystemExit('use no arguments for offline preflight, or --authorized-calibration after authorization')
    assert os.getuid() != 0 and os.geteuid() != 0
    binary = SCRATCH / 'calibration'
    with (SCRATCH / 'compile.log').open('w') as log:
        compilation = subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '6', '-module-cache-path',
                                     str(Path.cwd() / '.build/module-cache'), str(SOURCE), '-o', str(binary)],
                                    stdout=log, stderr=subprocess.STDOUT, timeout=120)
    if compilation.returncode:
        raise RuntimeError((SCRATCH / 'compile.log').read_text()[-12000:])
    preflight = subprocess.run([str(binary), 'self-test'], capture_output=True, text=True, timeout=5)
    if preflight.returncode:
        raise RuntimeError(preflight.stdout + preflight.stderr)
    print(preflight.stdout.strip(), flush=True)
    if sys.argv[1:] == ['--authorized-calibration']:
        result = run(binary)
        result['sourceSHA256'] = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
        result['supervisorSHA256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        result['compiler'] = subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True).strip()
        result['sdk'] = subprocess.check_output(['xcrun', '--show-sdk-version'], text=True).strip()
        result['osBuild'] = subprocess.check_output(['sw_vers', '-buildVersion'], text=True).strip()
        result['hardware'] = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
        target = ROOT / 'result.json'
        target.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(json.dumps({'summary': str(target), 'batches': [x for x in result['events'] if 'submissions' in x],
                          'observations': len(result['observations']), 'duration': result['workerAndObservationWallSeconds']}), flush=True)


if __name__ == '__main__':
    main()
