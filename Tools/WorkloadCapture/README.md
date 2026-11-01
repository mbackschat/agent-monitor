# Workload recording and analysis playbook

Use this development-only workflow to examine a representative workload when explicitly requested. The recorder uses production `NativeProcessReader` observations at a nominal 100 ms cadence, without thresholds, provider queries, arguments, environment or transcripts. The analyzer reads existing files only. These commands do not authorize an agent to start a live recording on its own.

## Prepare before the workload

```sh
git rev-parse HEAD
git status --short
swift build -c release --product monitor-workload-capture
.build/release/monitor-workload-capture --help
```

Keep the commit, dirty-checkout output, build configuration and exact recording command alongside the capture, outside Git. The header identifies format and OS, but cannot identify the source or changes compiled into the executable. Rebuild and refresh that provenance if the reader or recorder changes.

Preparation does not record processes; the executable is a development target, not a release product. If the default build stalls in `clang-stat-cache`, see the [restricted-environment guidance](../../docs/development.md#restricted-agent-environments) for the local fallback and cache/access setup.

## Record with explicit limits

```sh
capture_path="/tmp/agent-monitor-workload-$(date +%Y%m%d-%H%M%S).jsonl"
.build/release/monitor-workload-capture "$capture_path" 60 256
```

Use a fresh path for every capture; existing files and symlinks are refused. Defaults are 60 seconds and 256 MiB. Optional positional arguments select seconds and maximum MiB, capped at 300 seconds and 1,024 MiB. The first limit stops capture, so a disk allowance does not guarantee the requested duration.

For a longer recording, choose a new path and a larger explicit allowance, for example:

```sh
.build/release/monitor-workload-capture /tmp/agent-monitor-workload-long.jsonl 120 512
```

Ctrl-C or SIGTERM requests cancellation. Duration bounds new-scan admission; an in-flight read or write can delay shutdown. Slow scans skip missed slots.

Complete records are admitted within the byte allowance with room reserved for a footer. Native snapshots and encoded records still scale with population, so the disk limit is not a heap bound.

## Verify completion before interpreting

After flushing, the recorder prints actual/requested duration, persisted scan count and stop reason to stderr. Check this summary and the footer before treating the recording as a complete observation window:

| Stop / framing | Meaning |
| --- | --- |
| `duration`, exit 0 | Requested duration reached; polling coverage is still partial. |
| `sizeLimit`, exit 2 | The next acquired scan did not fit and was discarded. Preserve the partial recording; another capture needs a fresh path and explicit limits. |
| `cancelled`, exit 130 | Explicitly stopped early; use the actual duration. |
| `readerFailure` or exit 1 | Collection/finalization failed. A written failure footer does not make the run successful. |
| Missing footer | Interruption or failed finalization; do not present it as completed. |

The JSONL consists of a header, complete scan records and a footer. The footer measures persisted scans, elapsed time, recorder CPU and maximum listing gap/scan duration, excluding its own serialization/write cost.

Scans retain exact identities, parent PIDs, executable/name, birth/read times, cumulative/raw CPU, memory readings, native outcomes and clock/host anchors. Optional absent fields are unavailable, not zero. Listed PIDs/outcomes can include out-of-scope users; detailed samples exclude the recorder and are restricted to the current user.

## Analyze existing recordings

From the repository root, use the standard-library Python [analyzer](../../scripts/analyze-workload.py); it preserves inputs and invokes no live process APIs:

```sh
python3 scripts/analyze-workload.py "$capture_path"
python3 scripts/analyze-workload.py --top 20 /tmp/workload-a.jsonl /tmp/workload-b.jsonl
python3 scripts/analyze-workload.py --json "$capture_path"
```

Text is the default, `--json` emits a machine report to stdout, and `--top N` defaults to ten. Use `--json` for full contributor, read-count and listing-absence distributions.

Multiple inputs receive separate summaries; do not add their populations or CPU unless overlap and counter boundaries are independently reconciled. Output uses executable basenames rather than full workload paths.

Compare completion, cadence, population, CPU, footprint and native failure summaries before inspecting age/read-count distributions. Analysis retains per-lifetime and lifetime/name aggregates, per-scan scalar distributions and listed/failing PID-value sets; memory grows with those input dimensions and has no fixed heap cap.

### Interpret CPU accounting

CPU accounting follows exact PID/start identities and compatible raw counter increments. It requires raw user/system ticks, timebase and read ticks; incomplete tuples are counted as exclusions even when a floating-point `cpuSeconds` field is available. Initial cumulative CPU for pre-existing lifetimes is excluded; verified births after the recording baseline can contribute their initial cumulative CPU.

Per-executable buckets use the closing endpoint, with transition CPU flagged: a shell can exec Java or Node under the same PID/start identity, so first-name-only counts omit workers and an interval crossing an image change is not entirely attributable to its closing image.

Kernel-name fallback reads/lifetimes are counted separately when the executable is unavailable, preserving their weaker classification evidence. Counters cannot supply a final CPU oracle after a worker disappears.

### Interpret observed lifetimes

Age at a read is `sampledAt - startedAt`. Last-read age and first-to-last observation spans describe observed persistence, not complete lifetimes; one read does not establish a worker's duration.

For a newborn later absent from the current-user PID listing, the later scan brackets listing availability, not unconditional death. Disappearance, including `lookupUnavailable`, does not prove exit; reappearances and changed images require separate interpretation.

Distinct listed-but-never-read PID values have unknown lifetime/class, and repeated failures are observation counts. Never-listed workers leave no evidence, so these recordings cannot establish completeness or a loss percentage.

### Compare memory and overhead

Keep current footprint, sampled peaks and kernel peaks distinct; do not sum per-process peaks as simultaneous memory use. Host-minus-observed CPU is not measured agent loss, parent PID alone does not establish a session, and host Docker observations do not cover guest workers.

Recorder CPU includes its scanning/serialization/write work and can affect gaps; it is not the live monitor's collector/provider/UI cost.

## Preserve inputs and validate changes

Captures are created with owner-only permissions and contain process identities and executable paths. Keep originals and provenance outside Git, and preserve user-supplied recordings unless deletion is explicitly requested.

Retaining a dataset or findings in [research](../../docs/research/README.md) requires explicit authorization. Analysis does not authorize another recording or automatic cleanup.

Run the offline analyzer tests with `python3 -m unittest discover -s scripts -p 'test_analyze_workload.py'`. Recorder checks and related validation are in the [development guide](../../docs/development.md#on-demand-workload-recording).
