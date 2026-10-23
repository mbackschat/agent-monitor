# Bounded diagnostic recordings

Status: **unapproved**, 2026-10-23. Proposed recording feature dependent on [independent resource acquisition and background attribution](resource-accounting.md#acquisition-and-resolution). The user specified opt-in capture, runtime pause/resume, 50 MB uncompressed chunks, lossless compression and a configurable 250 MB total compressed budget. These are design requirements, not implemented controls. Storage estimates and unresolved compression questions belong in [the research note](../research/cpu-accounting.md#diagnostic-recording-size-estimates--2026-10-23).

## Recommendation

Record measurements and asynchronously captured context together in a versioned, documented sequence of independently compressed chunks. Start capture only on explicit user request. Keep recording independent of native acquisition and provider resolution, and allow analysis tools to combine every retained chunk into one qualified timeline. Reuse the async collector's evidence; recording does not introduce provider queries or substitute full presentation snapshots for source observations.

## Required contract

### Runtime controls

Capture defaults **off**. Users can start it, turn it off and resume it while monitoring continues, through CLI/TUI/native controls backed by the same recording state. Turning capture off seals the partial chunk and pauses that recording; resume appends to the same capture with a new segment. Sampling and background attribution continue independently. Closing the native panel, changing filters or freezing the display does not implicitly enable, pause or resume capture.

```swift
enum DiagnosticCaptureState: Sendable {
    case off
    case recording(captureID: UUID)
    case paused(captureID: UUID)
}

struct DiagnosticRecordingLimits: Sendable {
    var uncompressedChunkBytes: UInt64 = 50_000_000
    var compressedBudgetBytes: UInt64 = 250_000_000
}
```

Pause records the measurement cut-off and seals what has reached the writer; it does not wait indefinitely for attribution. Already accepted records may finish flushing/compressing after the control returns, with finalizing/failure status visible. Observations from the paused interval and newly arriving resolution updates are not accepted for recording while paused. Resume records an explicit gap and a fresh context checkpoint, including available resolutions for still-retained measurements. It must not silently backfill the paused interval or assign CPU accumulated across that interval entirely to the resumed segment. Unresolved evidence at pause remains marked; later updates preserve their actual observation times. The UI exposes state, finalization/errors, bytes retained, retained time range and the two effective limits.

### Content and chunk identity

Preserve monotonic counter observations, footprint and kernel peaks, exact process lifetimes, observed ancestry, allowlisted attribution evidence, later resolution updates, host context, sampling-rate changes and explicit coverage failures. Record observation times separately from resolution/write times. Include capture identity, acquisition-run/clock identity, chunk sequence, format version, time bounds and integrity information. Clock changes, PID reuse and out-of-order resolution cannot merge unrelated work. Existing restrictions on transcripts, tokens and environment collection remain in force.

Each retained chunk includes the context or checkpoint needed to interpret its records independently of already-evicted chunks. Within a chunk, unchanged metadata can be referenced rather than repeated per sample. Later attribution updates refer to stable observation/evidence identities; a combined reader applies them without duplicating CPU or replacing earlier evidence with a current-session guess. Updates whose original observations are no longer retained cannot recreate their measurements.

A documented reader/export contract combines any retained contiguous sequence, and explicitly marks missing chunks, pauses, retention truncation, corruption and unresolved context. Corrupt or unsupported data cannot silently become zero load. Format and compression identification must permit external analysis without a running monitor. Separate recordings do not share a monotonic clock implicitly.

### Limits, compression and retention

| Setting | Default | Meaning |
| --- | --- | --- |
| Uncompressed chunk limit | **50 MB = 50,000,000 bytes** | Maximum serialized input per chunk, including its context checkpoint; rotate at record boundaries before exceeding it. Pausing or ending a recording may produce a smaller chunk. Oversized records require explicit failure/coverage reporting, never silent truncation. |
| Compressed recording budget | **250 MB = 250,000,000 bytes** | Maximum total retained compressed bytes for the managed recording store, including in-progress compressed output, headers and control/index files. Starting another recording does not reset the budget. |

Both limits are ordinary user settings with clearly named CLI overrides and native/TUI settings access; changing them requires neither editing source nor rebuilding. CLI help and the usage guide must document defaults, decimal units, valid combinations, precedence and effective values. One shared definition owns the defaults. Record each setting change in the capture. Validate values before applying them; a smaller budget takes effect through explicit oldest-first retention and a smaller chunk limit seals the current chunk before further input. Reject combinations that cannot hold a valid context checkpoint and record.

Compression is **lossless**: decompression reproduces serialized records exactly, with no temporal downsampling or removal of evidence to improve the ratio. The chunk boundary uses uncompressed bytes even if compression is streamed, so a 50 MB raw file need not also be written to disk. Compression/writes run independently of acquisition with bounded buffering. A storage failure or compressor backlog is reported as a recording error/gap; it cannot stall the collector or create an unbounded raw-file queue.

Enforce retention against actual stored bytes, including output being written; do not budget from an assumed compression ratio. Delete the oldest complete chunks as necessary and preserve a boundary indicating the removed history. The newest surviving chunks remain independently interpretable. Lossless compression does not imply indefinite retention: rotation intentionally removes old history. Explicit exports are separate user-owned files outside the managed store and are not silently deleted by retention.

The requested 10:1 raw-to-compressed ratio is an estimate to validate, not a guarantee or a condition for enforcing the budget. At that ratio, full chunks are about 5 MB and roughly 50 fit before control overhead and partial chunks. Display measured ratio and retained duration rather than promising a fixed recording length.

### Validation requirements

Verify byte-identical compression round trips, combining chunks without double counting, fresh checkpoints after eviction/resume, delayed attribution spanning chunk boundaries, pause during pending writes, no capture before opt-in, repeated pause/resume, changed limits, incompressible input, interrupted writes and storage exhaustion. The actual compressed store must remain within its budget. Test with fake providers and owned workloads, including changing process identities and explicit acquisition gaps. Compare ratios and recording CPU/memory costs using realistic changing records, not repeated identical snapshots.

## Optional

Selection of a subset of retained chunks for export, provided required context is preserved and excluded time ranges stay explicit. Additional codecs may be considered after measuring ratio, encode/decode cost and external-tool compatibility; no codec or 10:1 result is established by this proposal.

## Excluded

Automatic recording at application startup, lossy aggregation disguised as raw capture, unlimited raw staging, automatic uploads and changes to user workloads. A new analysis UI is outside this proposal; the required capability is a documented, composable recording and reader/export contract.

## Material feasibility risks

The asynchronous evidence contract is a prerequisite; logging current reports cannot recover context never captured. Compression of already compact counters may fall well short of 10:1. Context checkpoints and churn increase bytes per observation. A bounded store can retain only a workload-dependent time span; compression backlogs, disk errors and pauses can create explicitly reported gaps. No recording format recovers work that the collector never observed.
