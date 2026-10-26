# Supplemental observations during inspection

Status: **unapproved**, 2026-10-26. Contract candidate for CPU-01; no native experiment or backend implementation is authorized by this proposal.

## Purpose and scope

Improve transparent discovery and measured CPU of short workers while the user inspects Mac or TUI, preserving complete 100 ms acquisition and independent five-second display. The [source review](../research/cpu-accounting.md#supplemental-inspection-observations-source-review--2026-10-26) identifies complete-scan assumptions that prevent safely treating a subset as another scan. This is additional polling, not a final-exit counter source or a guarantee of complete CPU.

Required: one accounting stream accepting complete scans and explicitly partial observations; supplemental same-user discovery independent of display filters and prior attribution; checked reads of new candidates and inspected lifetimes; bounded state; visible freshness and coverage. No workload launch integration is required.

## Observation contract

| Field / concept | Required semantics |
| --- | --- |
| Run identity and ordered observation number | One run and strictly increasing order across complete and supplemental batches. One counter ledger accepts each lifetime endpoint once. Ordering alone does not imply a complete scan or a missed read. |
| Batch kind | `complete` or `supplemental`; supplemental provenance distinguishes enumeration from targeted-only reads. |
| Read population | Enumerated PID values, admitted targets, attempted reads and deferred work are separate facts. Unvisited lifetimes are neither absent nor failed. Every counter read keeps the existing identity and UID verification bracket. |
| Complete-census endpoint | Latest completed full scan, its timestamp, observed population, failures, memory and frozen attribution/category for those readings. Complete means all acquisition attempts, not that every process was readable. A supplemental endpoint cannot replace it. |
| Per-lifetime evidence | Exact lifetime, counter timestamp, actual read outcome and closing-point attribution. Context retained for resolution is not a fresh measurement. |
| Timing and coverage | Complete start-to-start gaps, maximum gap and overruns remain separate from supplemental opportunities, successful reads, failed reads and deferrals. |

CPU deltas telescope through the one ledger. For example, A's cumulative CPU of 1.0 s at a complete scan, 1.3 s at a supplemental read and 1.5 s at the next complete scan yields 0.3 + 0.2 s once. B's omission from that supplemental read creates neither a departure nor a missing-read interval. A selected failed read is recorded as a failure; unrelated partial batches do not change another worker's missing-read status.

Newborn zero openings retain the approved birth, initial-baseline and eviction-floor rules. Only actual enumeration anchors qualify as listings; a targeted read cannot create a pre-birth listing anchor. Even an actual PID listing does not prove absence of a particular lifetime. PID-list differences discover new PID numbers, not every reused lifetime. Reuse without an intervening observed disappearance may remain undetected until a checked read; coverage must not claim otherwise.

A marker or inherited ownership claim for a new child needs a valid marker or freshly verified parent context, respectively; other valid adapter evidence remains admissible. Measurement does not wait for ownership: unresolved CPU remains included. Matching its parent PID to an old cache entry is insufficient. Additional context reads count against the same work allowance. Root corroboration uses valid contextual evidence, frozen at contribution closure, without adding those contextual rows as new memory/counter observations. Later enrichment never relabels accepted CPU.

## Inspection and freshness

Inspection is active while the Mac monitoring panel is open and displaying live results, or while the TUI live report is active. Pause holds its self-contained projection and ends supplemental scheduling for that view; complete acquisition continues under existing lifecycle policy. Closing or pause clears scheduling requests, not accepted measurements or history; resume reconstructs requests from current exact lifetimes. Run/scope replacement retains the existing history-reset policy. Existing live/static-icon behavior remains authoritative.

Current population and current memory, including the owner/CWD/executable attached to those readings, remain anchored to the latest complete census. New supplemental evidence must not move old census memory between categories. Supplemental CPU and timestamped sampled memory maxima enter recent accounting. A worker first observed after that census is labelled “since census”; it is not counted as confirmed current at that earlier census or as departed. Reports retain the census time separately from their final accepted accounting endpoint. At the next complete scan, a successfully read lifetime joins the new census; an absent or unreadable lifetime becomes no longer observed or uncertain according to its actual outcome, never confirmed exited. No mixed-time footprint sum may be labelled a fresh complete census.

Ordinary units and display windows close only at complete-scan boundaries; partial observations extend the open unit. Every accepted supplemental suffix drains on cancellation or failure, with its real endpoint and separate census, through the same conservation, compaction and history/report-pairing contract. History evicts whole units. Existing pressure remainders retain exact CPU, intervals and sampled memory maxima, qualified worker-count ranges and collapse spans. They must not treat census members or newly observed workers as absent merely because the last batch was partial; this does not promise indefinite per-worker detail. Candidate selection happens before counter admission. Before admission, bounded scheduling may defer candidates or release their queued detail with visible coverage counts. Once a reading is admitted, its CPU is conserved through normal storage or the existing explicit terminal-overload/drain contract; accepted counters and census state cannot be discarded as queue candidates.

Mac, TUI and JSONL expose batch coverage and the census/accounting time distinction; compact warnings or structured details carry the explanation. Inspection does not require a faster display refresh. Logging remains off and no new persistent history is created.

## Bounded scheduling and feasibility

Complete-scan deadlines are never rebased by supplemental work. One serial reader admits supplemental opportunities only between those deadlines, with no catch-up queue. Discovery considers new candidates regardless of known ownership or prominence. Follow-up reads target the exact current lifetime selected in a process inspector and successfully admitted new lifetimes until the next complete scan, with a fair share for discovery; a selected session does not implicitly request every member. Requests cannot use PID alone or survive identity replacement. Unserved candidates are deferred within bounded state and reported when their detail is released; they cannot silently disappear to satisfy the cost target.

A proposed initial experiment would compare one intervening opportunity at 50 ms against complete-only acquisition, before considering 25 ms opportunities. Missed intervening opportunities are skipped and counted, never shifted into catch-up work. The attempt allowance must include parent-context reads and enumeration, with a bounded candidate table charged to existing logical budgets. Neither frequency nor an attempt cap guarantees an OS deadline: an in-flight native read can overrun. Numeric work allowances require a separately approved experiment; they are not settled product defaults.

Acceptance requires independently measured discovery and exit-tail capture, unchanged conservation/attribution, achieved complete-scan start-to-start p99 ≤150 ms, full acquisition-work duration, reported maximum gaps/overruns and combined collector/helper cost ≤15% under representative load. Coverage wins if these conflict, but revised cost targets return to the user. Deterministic interleavings can establish correctness; they cannot establish the native coverage benefit or cost. Earlier native-fixture authorizations are consumed.

## Optional and excluded

Supplemental opportunity/read/failure/deferral counts and freshness are required, including skipped scheduling opportunities; only additional graphs of these counters are optional. No per-key or interaction history is recorded.

Excluded: privileged sources, SPI backends, final-exit recovery claims, selected-only discovery, slower or quieter-process-only baseline scans, independent ledgers, attributing unseen CPU by subtraction, new full-command capture, background supplemental reads when no view is inspecting, and unbounded PID or raw-snapshot queues.

## Recommendation

Review this partial-observation and census contract before implementation. It is broader than changing a timer because completeness currently controls liveness, memory, missing reads, attribution context and drain behavior. Require deterministic full/partial interleaving, PID reuse, failure, exec, label-change, pressure and cancellation oracles before requesting a bounded native comparison. If the extra readings do not improve coverage enough within an agreed cost envelope, keep the baseline and report that result; do not relabel the remaining loss as recovered CPU.
