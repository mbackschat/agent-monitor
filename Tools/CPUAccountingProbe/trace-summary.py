import argparse, json, xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path
parser = argparse.ArgumentParser(description='Summarize only owned worker PIDs from an xctrace thread-state export; use only with the matching controlled ledger.')
parser.add_argument('threads', type=Path)
parser.add_argument('ledger', type=Path)
args = parser.parse_args()
ledger = json.loads(args.ledger.read_text())
owned = {r['pid']: r for r in ledger['workers']}
refs = {}
totals = defaultdict(float)
rows = defaultdict(int)

def val(e):
    if e is None:
        return None
    if 'ref' in e.attrib:
        return refs.get(e.attrib['ref'])
    if e.tag == 'process':
        return val(e.find('pid'))
    return e.text
for event, e in ET.iterparse(args.threads, events=['end']):
    if 'id' in e.attrib and e.tag in {'pid', 'process', 'thread-state', 'duration', 'start-time', 'duration-on-core'}:
        refs[e.attrib['id']] = val(e)
    if e.tag != 'row':
        continue
    pid = val(e[4])
    pid = int(pid) if pid else -1
    if pid in owned:
        state = val(e[2])
        dur = int(val(e[3]))
        rows[pid] += 1
        if state == 'Running':
            totals[pid] += dur / 1000000000.0
    e.clear()
result = []
for pid, r in owned.items():
    result.append(dict(**r, trace_running_seconds=totals[pid], trace_rows=rows[pid], ratio=totals[pid] / r['cpu_seconds']))
out = dict(workers=result, oracle_seconds=ledger['total_cpu_seconds'], trace_running_seconds=sum(totals.values()))
out['ratio'] = out['trace_running_seconds'] / out['oracle_seconds']
print(json.dumps(out, indent=2))
