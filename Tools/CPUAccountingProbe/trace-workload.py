import json, os, resource, sys, time
rows = []
time.sleep(0.5)
for requested_cpu in [0.01, 0.05, 0.2, 1.0] if '--mixed' in sys.argv else [0.05] * 4:
    children = []
    for _ in range(4):
        pid = os.fork()
        if pid == 0:
            memory = bytearray(8 * 1024 * 1024)
            for offset in range(0, len(memory), 4096):
                memory[offset] = 1
            start = time.process_time()
            while time.process_time() - start < requested_cpu:
                pass
            os._exit(0)
        children.append(pid)
    for pid in children:
        _, status, usage = os.wait4(pid, 0)
        rows.append(dict(pid=pid, parent=os.getpid(), status=status, requested_cpu_seconds=requested_cpu, cpu_seconds=usage.ru_utime + usage.ru_stime, allocation_bytes=8 * 1024 * 1024))
    time.sleep(0.1)
time.sleep(0.5)
print(json.dumps(dict(parent=os.getpid(), workers=rows, total_cpu_seconds=sum((r['cpu_seconds'] for r in rows)))))
