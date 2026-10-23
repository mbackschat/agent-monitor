import ctypes as C, json, os, select, time
lib = C.CDLL('/usr/lib/libproc.dylib', use_errno=True)
mach = C.CDLL('/usr/lib/libSystem.B.dylib')

class Usage(C.Structure):
    _fields_ = [('uuid', C.c_uint8 * 16)] + [(n, C.c_uint64) for n in ['user', 'system', 'pkg', 'interrupt', 'pageins', 'wired', 'resident', 'footprint', 'birth', 'exit', 'child_user', 'child_system', 'child_pkg', 'child_interrupt', 'child_pageins', 'child_elapsed', 'read', 'written']]

class Timebase(C.Structure):
    _fields_ = [('numer', C.c_uint32), ('denom', C.c_uint32)]
b = Timebase()
mach.mach_timebase_info(C.byref(b))
scale = b.numer / b.denom / 1000000000.0
lib.proc_pid_rusage.argtypes = [C.c_int, C.c_int, C.c_void_p]
results = []
for iteration in range(40):
    info_r, info_w = os.pipe()
    gate_r, gate_w = os.pipe()
    out_r, out_w = os.pipe()
    supervisor = os.fork()
    if supervisor == 0:
        os.close(info_r)
        os.close(gate_w)
        os.close(out_r)
        child = os.fork()
        if child == 0:
            os.close(info_w)
            os.close(out_w)
            os.read(gate_r, 1)
            start = time.process_time()
            while time.process_time() - start < 0.01:
                pass
            os._exit(0)
        os.write(info_w, str(child).encode())
        os.close(info_w)
        os.close(gate_r)
        _, status, usage = os.wait4(child, 0)
        os.write(out_w, json.dumps(dict(cpu_seconds=usage.ru_utime + usage.ru_stime, status=status)).encode())
        os.close(out_w)
        os._exit(0)
    os.close(info_w)
    os.close(gate_r)
    os.close(out_w)
    child = int(os.read(info_r, 100))
    os.close(info_r)
    queue = select.kqueue()
    event = select.kevent(child, filter=select.KQ_FILTER_PROC, flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT, fflags=select.KQ_NOTE_EXIT)
    queue.control([event], 0, 0)
    os.write(gate_w, b'x')
    os.close(gate_w)
    events = queue.control(None, 1, 5)
    usage = Usage()
    rc = lib.proc_pid_rusage(child, 2, C.byref(usage))
    error = C.get_errno()
    expected = json.loads(os.read(out_r, 4096))
    os.close(out_r)
    os.waitpid(supervisor, 0)
    queue.close()
    results.append(dict(event=bool(events), readable=rc == 0, error=error if rc else None, observed_cpu_seconds=(usage.user + usage.system) * scale if rc == 0 else None, expected_cpu_seconds=expected['cpu_seconds']))
print(json.dumps(dict(method='Independent observer registers before worker starts; supervisor immediately wait4 reaps; 40 owned 10 ms CPU workers', results=results), indent=2))
