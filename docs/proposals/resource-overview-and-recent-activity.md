# Resource overview and recent activity

Status: **unapproved**, 2026-10-24. Addendum to [resource accounting](resource-accounting.md), informed by the user's 2026-10-24 feedback and discussion. The user accepted the Main contributors direction and requested this consolidated design; the detailed contract, defaults and Explorer scope remain proposed. This document does not extend the original first-delivery implementation authorization or approve [diagnostic recording](diagnostic-recording.md). Open work belongs in [PLAN.md](../../PLAN.md#resource-accounting-priority).

## User input and intent

| User input from the 2026-10-24 discussion | Design consequence |
| --- | --- |
| Requested precise acquisition without a 0.1-second UI refresh, then asked how display and acquisition handle short-lived processes. | Preserve the implemented independent acquisition/display windows; recent-history retention extends inspection time rather than slowing acquisition or replaying every sample into the UI. |
| “The app #2 goal is to get user orientation and overview,” after reporting an unusable list of `0,0%` processes and a `99+` badge. | Comprehensive accounting remains the first priority; the default presentation must explain meaningful CPU and memory contributors rather than expose the full census. |
| Accepted “Main contributors,” but questioned why zero-CPU processes appear. | CPU and memory relevance are independent. Hide negligible contributors by default, but retain a zero-CPU process that holds substantial memory. Zero CPU is not proof of exit. |
| Workers disappear on refresh before their contribution can be understood; requested recent statistics and feedback linking them to the parent session. | Retain recent measured work and its session evidence across display windows. Keep a session's burst inspectable after its current CPU falls. |
| Asked for a helpful population map, trees and Explorer subviews in their own windows. | Separate session ownership, runtime-family summaries and observed ancestry; provide progressive disclosure beyond the compact overview. |
| Requested session counters for processes, CPU, memory and stopped processes, asking whether the stopped count should be monotonic. | Define each population, time range and reset boundary. Distinguish current observations, rolling distinct counts and optional cumulative counts; disappearance does not establish termination. |
| Requested Java and Node workers to be counted together despite different PIDs. | Group by verified executable/runtime family; deduplicate by exact process lifetime, preserving individual workers below the family summary. |
| Confirmed that most of this should also apply to TUI. | Share counting, aggregation, recent history and contributor selection; vary navigation and layout between frontends. |
| Suggested that the log/recording proposal could support recently gathered data and later statistics. | Live recent history must work without recording; persisted observations can extend the investigation period through a separately specified analysis view. |

The requested rename from **Sessions** to **Group by agent session** is already implemented in `28f981c`; it is not pending scope here. Current acquisition/display behavior is documented in [independent display windows](../architecture.md#independent-display-windows).

## Findings and rationale

The [dated population findings](../research/menu-bar-load-cost.md#population-and-overview-feedback--2026-10-24) separate the user's screenshot, source inspection and a single aggregate process-table check. The app currently defaults to agent-associated scope with both resource filters off. Its badge counts unfiltered observed agent-associated lifetimes, including historical contributors in the displayed window, rather than busy workers or exact sessions. A large helper population is plausible; the check did not reconcile the exact `99+` badge or validate every attribution.

The present scalar history preserves overall resource trends, not a browsable archive of per-session workers. One-second accounting windows retain disappeared workers only within the delivered window; the next window can remove the evidence needed to explain a burst. This is a presentation/history gap distinct from work that acquisition never measured.

Recommendation: a default contributor overview plus bounded recent history, independent of acquisition cadence and disk recording. This reduces idle-process noise without sacrificing observed totals and makes bursts understandable after they finish. A process tree alone cannot solve ownership uncertainty, and a persistent recording alone cannot provide an always-available live overview when capture is off.

## Required contract

These are requirements of the proposed extension, not claims about the shipped app.

### Main contributors and population navigation

The default interactive view prioritizes meaningful CPU or memory contributors; **Show all** exposes the full observed population with explicit shown/hidden counts. Zero CPU alone cannot exclude a memory-heavy process. Unavailable readings are not idle readings: keep incomplete population totals and unresolved ownership visible even when individual rows are collapsed. Display selection never changes acquisition, attribution or advertised population totals.

Recommend an initial overview of approximately ten top-level entries, with session groups collapsed and independently accessible CPU and memory contributors. The exact ranking, relevance floors, tie handling, stability and overflow rule remain open below; ten is not a license to silently hide a significant contributor. Pins and explicit inspection retain their existing behavior. Manual CPU/memory thresholds remain available and distinct from automatic overview selection.

Use session → executable/runtime family → process as the summary hierarchy. Exact session identity remains provider-qualified, with corroborated root-session grouping following the existing contract. Shared runtimes and unresolved associations occupy explicit separate sections. Grouping unresolved entries for navigation does not assign them a common session. Project paths provide context, never ownership evidence.

Observed process ancestry is an alternative relationship view within exploration, not the ownership hierarchy. Preserve exact lifetime links and observation times; missing parents, reparenting and uncertain historical ancestry stay explicit. A parent runtime can be shared, so its descendants cannot automatically become one exact session. Cross-links and multiple navigation views must not double-count resources.

Recommend a compact Mac overview and a separate Explorer window for session statistics, worker families, individual workers and ancestry. TUI exposes the same data through expandable groups and a details view; it does not require a separate native window. The Explorer window arrangement is an optional presentation choice, not a prerequisite for shared statistics.

### Current and recent session statistics

Recommend a rolling **60-second** recent period, beginning with the actually available collection range and visibly shortened after startup or retention loss. This is a proposed usability default, not a validated memory budget. Session summaries remain visible when recent meaningful work would otherwise disappear from the current overview. Historical work never masquerades as current load.

| Statistic | Public meaning |
| --- | --- |
| CPU now | Unique eligible CPU contributions divided by the latest enclosing display-window duration, in one-core percent; preserve point-candidate and uncertain ownership qualifications. |
| Memory now | Latest available physical footprints of members observed in the final scan, with observation spread and incomplete readings qualified. Departed members contribute no current footprint. |
| Processes now | Distinct process lifetimes observed in that scan, not proof that each is executing or that every live process was readable. |
| Recent workers | Distinct workload lifetimes observed in the retained recent interval, including those still observed now. Agent runtimes/shared services remain separately identified; do not count every runtime as a short-lived worker. |
| No longer observed | Recent worker lifetimes absent from the final scan. This rolling value may decrease through return or expiry; it is not a confirmed-exit count. |
| Recent CPU-seconds | Unique accepted measured CPU work whose endpoints are eligible within the actual recent interval, including departed workers. Earlier-opening recovery stays separate; no proration or addition of displayed percentages. |
| Largest sampled worker footprint | Maximum available physical-footprint reading retained for a worker in the period, not its last reading, a sum over time, or a claim that the true peak was captured. Keep the kernel task peak distinct. |
| Largest contributors | Worker families and individual lifetimes ranked by their recent measured CPU or sampled footprint, retaining available workload descriptions. |
| Coverage | Actual retained range, missing observations, recovery exclusions, uncertain attribution and retention loss affecting interpretation. No missing data becomes measured zero. |

For example, a session can show `CPU now 0% · Memory now 1.6 GB · 8 processes observed` alongside `Last 60 s: 24 workers no longer observed · 6.3 measured CPU-seconds`. These are illustrative values, not retained measurements. Expanding recent workers shows their family, name, exact identity, first/last observation, measured CPU, sampled footprint maximum and original attribution evidence.

“Recent worker” does not assert a verified short lifetime. First appearance is not necessarily birth, last observation is not exit, and their difference is only an observed span. Only verified birth/exit evidence can support a true lifetime claim. Historical rows retain the existing prohibition on process actions.

### Runtime-family grouping and counting

Java processes belong in a Java family and Node processes in a Node family when executable/runtime evidence supports that classification. PIDs, versions and installation directories do not by themselves create distinct families. An arbitrary display name such as `node_repl` is insufficient to certify Node; retain the observed executable/name when recognition is uncertain. Family recognition does not establish provider or session ownership.

Count a worker once per population using its exact PID/start-time identity within the acquisition run. Repeated readings do not add workers, while PID reuse creates a new lifetime. Preserve available JAR/script/tool descriptions as details below the family; no new unrestricted argument or environment capture is implied.

Retain the family and ownership evidence applicable to each observation/contribution. A later exec or session reassignment cannot relabel all earlier work. If one lifetime appears in more than one family or ownership category over the recent interval, disclose that membership change and deduplicate the parent population; child distinct counts need not be additive. Uncertain CPU is counted once in the appropriate uncertainty population, not assigned in full to every candidate session.

### Retention, shared behavior and recording

Recent statistics consume retained accounting contributions and acquisition-time memory observations, not only the one-second displayed snapshots. Otherwise a footprint burst that ends before display can disappear from history. Preserve original observation/contribution identities, timestamps and point labels across coalescing; recompute interval eligibility from endpoints when the recent boundary advances. Retention has explicit record/text/heap bounds as well as a time horizon, with shortened coverage or loss reported visibly. Presentation retention cannot block acquisition or silently discard measured work while claiming full coverage.

The counter/evidence source remains in core; UI-neutral population grouping, recent-statistic projections and inspection state are shared. Mac and TUI must report the same numbers for the same observations, scope and time interval. Frontend windows do not create independent samplers or competing totals. Selection and pause follow the shared inspection contract; pause freezes the displayed historical range while collection continues.

Live recent history is available with recording off. The [recording proposal](diagnostic-recording.md) remains the authority for opt-in persistence, raw counter replay, attribution revisions, gaps and retention boundaries. Do not introduce a second competing raw-record format or substitute presentation summaries for authoritative recording observations. A later recording-backed Explorer must expose the retained capture range and gaps; that analysis UI is not currently included in the recording proposal. Neither feature recovers never-observed workers or final exit CPU.

## Optional and excluded scope

| Capability | Recommendation and boundary |
| --- | --- |
| Separate native Explorer window | Recommended for room to investigate; detailed window/navigation design remains open. TUI uses its own hierarchy/details navigation over the same data. |
| Peak observed session footprint | Optional extension: largest retained per-scan sum under the ownership evidence available at that scan, explicitly labeled a point-attributed observed aggregate with read spread. Never sum individual worker peaks or claim exact simultaneity. The original accounting delivery excludes historical session peaks; an unqualified/interval-supported historical peak remains gated by its stronger evidence requirements. |
| Monotonic total observed since collection started | Optional: distinct lifetimes, with an explicit start/reset boundary and bounded deduplication guarantees. It is not total session lifetime activity when collection began late. Recommend rolling counts first; do not claim exact monotonic distinct counts after identity retention has been lost. |
| Configurable recent range and longer recording-backed analysis | Optional after the basic bounded recent view; no automatic disk recording is implied. |
| Confirmed stopped-process counter | Excluded without reliable exit evidence. A monotonic disappearance-event count would count events rather than distinct stopped processes and is not recommended as the overview counter. |
| Attribution guesses and fabricated completeness | Excluded: cwd-based ownership, PID-only identities, summing duplicate views, treating unreadable processes as idle, or hiding coverage gaps to produce a cleaner display. |
| Additional product expansion | No new process actions, live provider probes, automatic exports/uploads, persistent capture by default, acquisition adaptation or revised wire schema is authorized by this addendum. |

## Recommendations requiring resolution

| Choice | Recommendation and rationale |
| --- | --- |
| Contributor selection | Rank both CPU and memory within their stated populations, initially around ten top-level entries, with an explicit route to additional contributors. Set and validate relevance/stability rules against quiet-memory-heavy and burst-heavy cases before selecting exact cutoffs. A CPU-only ranking cannot explain memory pressure. |
| Recent period and bounds | Start with 60 seconds; establish explicit retained-data/heap limits and visible overflow semantics. A time bound alone is not a memory bound under process churn. |
| Badge | Make activity/resource information primary and the total observed-process census secondary. Choose its exact representation with the overview layout; changing filters must not silently redefine the meaning of an existing badge. |
| Worker families | Normalize only from trustworthy executable/runtime evidence and preserve an unknown family. Define verified Java/Node recognition and exec-change handling before promising the grouping; avoid unbounded tool-specific heuristics. |
| Counts and memory peaks | Require rolling recent counts and per-worker sampled maxima first. Keep cumulative distinct counts and session peak extensions optional until their retention and attribution guarantees are settled. |
| Recording relationship | Share accounting identities and evidence now; retain the independent recording contract. Review longer-term analysis as an explicit extension instead of making disk capture a requirement for live orientation. |

## Acceptance semantics and material risks

The same fixtures must yield the same session/family totals in Mac and TUI; hiding rows cannot change them. Observed bursts remain inspectable after later idle display windows. PID reuse, repeated/coalesced input, reappearance and expiry must not inflate counts or CPU. An idle memory-heavy worker remains discoverable; unresolved ownership and unavailable measurements stay explicit. Per-worker memory maxima must include retained acquisition observations between display refreshes, while current memory excludes departed workers. Group/family changes cannot retroactively reassign earlier contributions, and parent population totals deduplicate overlapping historical categories.

Actual ranking usability, family recognition coverage, bounded-history cost and the exact native/TUI exploration layouts remain unvalidated. The population check motivates the problem but is not an attribution oracle. Complete churn/exit capture and interval-supported historical ownership remain the accounting proposal's existing open gates; a more helpful overview does not close them.
