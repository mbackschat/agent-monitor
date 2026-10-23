# Bounded diagnostic recordings

Status: **unapproved**, 2026-10-23. Dependent on [independent acquisition and historical attribution](resource-accounting.md). User requirements: opt-in runtime capture/pause/resume, 50 MB uncompressed chunks, lossless compression, a configurable 250 MB compressed-store limit and combined later analysis. These controls are not implemented. [Size estimates](../research/cpu-accounting.md#diagnostic-recording-size-estimates--2026-10-23) remain conditional; [review assessment](../research/cpu-accounting.md#external-review-assessment--2026-10-23) records the corrections and remaining gates.

## Recommendation

Use versioned UTF-8 JSON Lines in independently completed gzip members, through the system zlib, as the initial interoperability baseline. Multiple members form a chunk; multiple chunks form a capture. Raw counter observations and recorded attribution/evidence revisions have separate authority, and a reference reader re-derives CPU with the collector's versioned counter-acceptance rules and consumes recorded attribution revisions as authoritative labels. Do not also store authoritative derived CPU totals that can disagree with replay. Preserve raw integer values exactly; 64-bit counters/timestamps use documented decimal strings rather than requiring tools to round through floating-point JSON numbers.

## Required contract

### Start, pause, resume and stop

Capture defaults **off**. Start creates a new capture ID in the current acquisition run. Pause stops accepting new measurement scans; resume continues that capture with an explicit gap and fresh baseline. Stop finalizes it and returns to off; a later Start creates another capture. CLI/TUI/native hosts reuse the state model and service within their own process. There is no cross-process control or implicit IPC: a CLI cannot pause the separate app's capture, and the store lock rejects competing writers. Display freeze, filtering and closing the native panel do not change recording state. Acquisition and background resolution continue during recording pauses.

A recording, paused or finalizing capture holds an acquisition-lifetime lease in its host process. In the Mac app this overrides static-icon closed-panel cancellation: closing/reopening the panel keeps the same acquisition run alive, with visible status explaining that capture keeps collection active even while paused. The icon may remain visually static. Successful stop or terminal failure releases that lease; normal static-icon lifecycle applies again if no other collection consumer remains. Explicit application quit still ends the run and finalizes/interruption-marks the capture as described below.

```swift
enum FinalizationDestination: Sendable { case paused, off }

enum DiagnosticCaptureState: Sendable {
    case off
    case recording(captureID: UUID)
    case paused(captureID: UUID)
    case finalizing(captureID: UUID, cutoffScan: UInt64, then: FinalizationDestination)
    case failed(captureID: UUID?, reason: String)
}

struct DiagnosticRecordingLimits: Sendable {
    var uncompressedChunkBytes: UInt64 = 50_000_000
    var compressedBudgetBytes: UInt64 = 250_000_000
}
```

A pause/stop request establishes a cut-off at the last complete scan accepted by the recorder, identified by acquisition-run ID and scan sequence. Every accepted scan at or before the cut-off is drained before successful finalization; an in-flight scan not accepted by that point is excluded. Queued data is not discarded merely because it has not reached the writer. Finalizing remains visible; requests cannot race a resume against sealing. Storage failure, queue exhaustion or a finalization deadline reports failure and the last confirmed complete scan, never a successful full capture. The initial finalization deadline is five seconds, a proposed bounded failure policy to validate under recording load.

While paused, keep bounded resolution updates referring only to already-recorded, still-retained observations. Persist them on resume or stop with original evidence/observation times; do not record measurements from the pause. The recorder retains the required references independently of the live UI's history. Overflow or an evidence retention limit is an explicit unresolved/recording gap, never a silently dropped correction. Resuming starts a new measurement segment with fresh baselines; it cannot turn CPU accumulated during the pause into resumed load. Pending resolutions need not all finish before stop: record unresolved status and close at the declared cut-off/deadline.

A capture belongs to one acquisition run and ends with that run. Clean shutdown attempts finalization; a crash produces an interrupted capture. It may be recovered for analysis but not resumed as though clocks/baselines were continuous. Start another capture after restart; tools may align wall time while preserving distinct runs. Show state, finalization/errors, effective limits, retained byte count/time range and actual compression ratio.

### Records, clocks and checkpoints

Record listing times and complete scans with per-process read times, exact lifetime identity, optional verified execution generation, cumulative CPU, footprint/kernel peak, host counters, verified ancestry and native failure outcomes. Include listed-but-unreadable PIDs with operation/status/errno, without inventing an identity. Preserve allowlisted evidence, supported validity intervals and versioned resolution updates. Missing execution generation remains unknown. Later evidence may revise ownership, not raw counters. Persist support per provider/runtime/session/terminal/ancestry level, including point times, evidence IDs, resolution revision and adapter version.

Every chunk identifies format/acceptance-rule versions, capture and acquisition-run IDs, boot-session identity, timebase, chunk sequence and scan range. Each scan records Mach absolute/continuous and wall-clock anchors, with capture ordering/read spread; clocks are not assumed atomically sampled or interchangeable. Absolute time defines the existing CPU arithmetic, continuous time exposes sleep gaps, and wall time enables external alignment. Updates refer to original run/scan/observation/evidence IDs and verified lifetime/epoch where available.

Chunks and gzip members contain complete scans; no scan is split across a retention boundary. A chunk's opening checkpoint carries context and counter baselines with their **original observation IDs**, marked as references rather than new measurements. It supplies enough evidence to interpret the following scans without an evicted predecessor. The reference reader deduplicates IDs across checkpoints/chunks, derives each accepted delta once and preserves gaps. A newborn-zero baseline carries its original listing ID, verified birth and eligibility state; it is not a measured zero process sample. Missing required pre-birth history makes the delta unavailable, not inferred from the first retained PID appearance. Counter baselines before capture start, resume or an evicted retention boundary are context only: cross-boundary CPU remains separately labeled and excluded from the retained interval's rate. Joining consecutive chunks from the same uninterrupted segment can restore valid continuity without double counting.

Recorded attribution revisions are authoritative for what this capture reported. The reference reader applies their explicit revision/target relationships and support levels; it must not re-run current adapters or infer ownership from incomplete saved provider inputs. Raw counters remain authoritative for CPU recomputation. Full provider listing output is not required or implicitly persisted. An external tool may offer a separately labeled alternative analysis with its own method/version, but must preserve and distinguish the recorded interpretation.

Later resolution updates may target earlier retained chunks. Readers combine available revisions and report incomplete context when the required update was not supplied. Each chunk preserves previously known relevant revisions in its checkpoint; a standalone old chunk cannot claim knowledge of future updates. Evicting older chunks must not orphan the baselines or context needed by surviving chunks. Updates for evicted observations do not recreate CPU history.

The reference reader validates versions, member checksums, scan completion, IDs and ordering. It exposes pauses, eviction boundaries, missing chunks, errors and unresolved ownership. Unsupported/corrupt data never becomes zero. Raw decompression is useful for inspection, but a successful `zcat` alone is not validation of the recording contract.

### Chunk framing and interrupted writes

Each chunk is a concatenation of complete independent gzip members, each containing complete JSONL records/scans and a member summary identifying its scan/event range. Complete a member at most one second after its first accepted scan, or earlier at a 4 MB uncompressed member limit, whichever can be reached at a complete-scan boundary. A chunk may contain many members up to its raw byte limit. A checkpoint plus one scan that cannot fit a member is rejected visibly; no record or context is silently truncated. These member limits are proposed engineering bounds requiring validation, not measured optimums.

Gzip CRC/length checks detect ordinary corruption; they are not authenticity guarantees. An active chunk has a temporary name and becomes sealed by rename only after its final complete member and close succeed. On opening the store, account for temporary files before starting capture, recover the longest checksum-verified complete prefix and mark any trailing partial member as lost. Invalid interior data ends the trustworthy prefix unless a future format explicitly supports resynchronization. Recovery/truncation must not create an unbudgeted second copy. Do not claim power-loss durability merely because a member was flushed or renamed; report recovery to the last verified persisted boundary.

### Store ownership, disk bounds and settings

| Setting | Default | Meaning |
| --- | --- | --- |
| Uncompressed chunk limit | **50 MB = 50,000,000 bytes** | Maximum serialized raw input, including checkpoint and member summaries. Rotate at complete-scan/member boundaries before exceeding it; partial chunks are valid. |
| Compressed store budget | **250 MB = 250,000,000 bytes** | Sum of logical file lengths of all managed chunks, active/temporary files, control/index files and temporary control replacements. A new capture does not reset this store-wide budget. |

One process holds an exclusive store lock while writing, recovering, configuring or evicting. A second CLI/TUI/app writer fails visibly; it cannot override the store's limits or delete another writer's chunks. The initial reader consumes a paused/stopped capture or an explicit exported copy. Reading a changing store is not a consistent snapshot: detect missing/replaced chunks and report it as such. Analysis cannot seize writer ownership or hold acquisition waiting for an unbounded read lease. Different stores are independent explicitly selected destinations, not an automatic way to bypass the configured store budget.

The store control record owns its effective limits. Document defaults, decimal units, validation and precedence in CLI help and usage. Provide shared user settings and CLI overrides; dedicated native/TUI limit editors are optional. Editing limits requires neither source changes nor rebuilding. Applying overrides to an existing store is an explicit configuration operation under its writer lock, with the resulting retention behavior visible. A reduced budget evicts oldest complete chunks before further input; if the active content/control reserve cannot fit, reject the change rather than exceed it. Record successful effective-limit changes as small control events.

Before accepting a member for disk output, reserve its worst-case compressed size for the exact gzip settings, plus closing/control-update overhead. Enforce `existing logical bytes + reserved new output/control bytes <= store budget` before every write, evicting oldest complete chunks as necessary. If the active chunk prevents the next member fitting, seal it early and retry retention; 50 MB is an upper bound, not a promise that every chunk reaches that size. Reject budgets smaller than the worst-case checkpoint plus one complete scan/member and control reserve. Decrease a reservation to actual bytes only after completion; incompressible expansion must not exceed the limit. The gzip bound must be valid for the actual member finishing policy, not an assumed ratio or arbitrary flush sequence.

Record the retained boundary when old chunks are removed. Lossless compression preserves serialized records exactly; eviction deliberately removes history. Streaming compression avoids a duplicate raw-file archive. User exports are outside the managed store, explicitly identified as such and never automatically evicted. A logical-byte budget does not guarantee equal allocated disk space or release of filesystem snapshots. Use a private Application Support store, not Caches, with backup exclusion requested; do not claim this removes pre-existing snapshots or excludes every external backup system.

### Memory, data access and failure bounds

Bound pending serialized input, active raw member input, paused resolution updates and recorder indices separately from disk storage. Proposed initial limits are 16 MB total for queued/active serialized input, with at most 4 MB of that reserved for paused updates, and a 4 MB raw member maximum. Compressed staging is limited to the validated worst-case output for one member; codec working allocations have a separate 2 MB cap. Metadata/index structures need their own measured bound before implementation acceptance; serialized-byte limits alone do not bound Swift heap overhead or core evidence retention. Never queue unbounded raw files or block acquisition on compressor throughput.

A full queue, oversized scan/checkpoint, failed lock, disk error or failed budget reservation creates a visible recording failure with the last confirmed sequence. If the filesystem cannot accept an error marker, the unclean end remains detectable on recovery. Do not continue silently dropping scans. Resume after failure requires an explicit recovery/new segment decision; an unresolved failure is not automatically retried.

Create the store with mode 0700 and files with mode 0600. Persist only the existing allowlisted evidence; no transcripts, messaging tokens or unrestricted environment capture. Cwd/project paths, terminals and session/socket identifiers are diagnostic context and are disclosed as recorded fields. Full argv is excluded by default and requires a separate capture-specific opt-in; the live display's command option does not enable persistence. No automatic upload.

### Validation requirements

Verify byte-identical round trips, replay equivalence with accepted live deltas, baseline deduplication, missing-chunk and retention boundaries, late evidence across chunks/pause, concurrent writers, pause/stop cut-offs, queue exhaustion, changed limits and incompressible expansion. Truncate at every member region and during control replacement; readers must distinguish a verified prefix from a complete capture. Validate multi-member decoding with standard tools and the reference reader, including trailing garbage and incomplete members.

First measure actual serialized bytes per complete scan and retained duration at the selected cadence, including context/checkpoint overhead. Then measure CPU/memory, compression ratio and backlog under representative changing records and saturated owned load. Test default-off, start/pause/resume/stop and failed/finalizing transitions without a running real provider, including static-icon panel close/reopen during recording, pause and finalization. Verify that stop/failure releases collection ownership, explicit quit ends the run, recorded attribution survives adapter upgrades and point versus interval-supported subtotals remain distinct. Fix acceptance limits before evaluating runs. All numerical engineering caps above require these tests; documentation and gzip availability do not establish readiness.

## Optional

Native/TUI editors for limits, selective export and alternative codecs after comparative evidence. The initial required controls are start/pause/resume/stop, simple shared settings/CLI overrides and a reference reader. A new analysis UI is outside scope.

## Excluded

Automatic startup recording, cross-process capture control/IPC, lossy aggregation disguised as raw capture, unlimited staging, cross-run resume pretending continuity, automatic upload and changes to user workloads. Do not assume 10:1 compression: the disk budget uses actual bytes regardless of ratio.

## Material feasibility gates

The asynchronous evidence and counter contracts are prerequisites. Frame/checkpoint size, memory caps, codec bounds, persistence/recovery behavior and compatibility remain to be validated. The prior 64–128-byte size estimates describe a hypothetical compact format, not this proposed JSONL encoding. Compression ratios and retained duration require new measurements. No recording recovers work never observed by the collector.
