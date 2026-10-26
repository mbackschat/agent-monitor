# Project plan

## Resume point

Finish the [product goal](docs/product.md): identify agent → session → CWD → executable → CPU/memory in Mac and TUI, with particular attention to short workers during inspection. Shipping acceptance remains open. Keep only unfinished work, next actions and pending decisions here; remove completed entries once their durable outcome is documented. [Architecture](docs/architecture.md) owns implemented contracts, [development](docs/development.md) owns validation procedures, and [research](docs/research/README.md) owns dated evidence.

## Open follow-ups

### Resource accounting priority

- [ ] **CPU-01 — Close coverage, sustained-load performance and memory acceptance.** The first [accounting delivery](docs/proposals/resource-accounting.md) is authorized. Preserve measured CPU, exact lifetimes, frozen attribution and explicit unknown/missing work. Do not slow baseline acquisition, exclude processes or change totals through display filters.

| Priority | Next action | Required evidence / blocker |
| --- | --- | --- |
| Short-worker coverage | Obtain approval of the amended [held-reading contract](docs/proposals/inspection-observations.md) for default-off deterministic implementation; keep complete 100 ms acquisition and five-second display. | Cold review recommends admission only at complete scans, census-only current memory and no selected-process reads. Historical evidence must not borrow later ownership. Benefit is unmeasured; discovery-only does not resolve existing workers’ exit tails. Native trials require separate authorization. |
| Sustained cost/cadence | After implementation stabilizes, profile the clean optimized build under naturally occurring representative load. | At least ten minutes, roughly 650 processes, providers enabled, helpers included, no concurrent builds/tests; ≤15% of one core and p99 acquisition ≤150 ms. Report maximum gaps and overruns in every window. A quiet passing run is insufficient. |
| Memory | Complete owned-state/scratch accounting and establish a measured operating envelope; resolve input buffering without a fork. | Logical per-stage caps are not a process-wide heap ceiling. [Retained-state findings](docs/research/menu-bar-load-cost.md#retained-state-ownership-audit--2026-10-26) and TUI-INPUT-01 remain relevant. Command-array sharing is lower priority and requires explicit ownership before charge discounts. |
| Publication pressure | Verify realistic bridge delays and publisher stalls while preserving history/report pairing. | Deterministic conservation/collapse guards do not establish native cadence or heap cost. |
| Native acceptance | Complete MENUBAR-01/03 and UX-01. | CLI profiles do not establish closed-panel App Nap, native cost or physical interaction. |

The completed short-worker fixture confirms substantial loss despite timely polling. [Coalition research](docs/research/cpu-accounting.md#ordinary-app-launch-and-coalition-isolation--2026-10-26) provides no unseen-session attribution; further coalition trials are not the recommended next step. Inspection-focused observations are a candidate, not an implemented guarantee. General transparent coverage remains required, and older summaries must disclose incomplete measurements.

- [ ] **UX-01 — Validate the responsibility workflow in both interfaces.** Use the [review procedure](docs/development.md#resource-overview-ux-review), including multiple contributors/CWDs, departed workers, memory-heavy idle work, uncertainty, nested sorting and contextual actions. Overview and process inspection must be checked separately; legacy process-view feedback remains open below. Complete headless review and the user's narrow/wide Mac/TUI smoke checks. Supply a focused external-review prompt at the next review checkpoint.

### Existing validation follow-ups

- [ ] **TUI-INPUT-01 — Bound ordered input end to end.** The [proposal](docs/proposals/bounded-terminal-input.md) is on hold for an official upstream fix or verified supported-public-API solution. Reader/parser/runtime queues and producer-side paste ordering remain open. The [no-fork decision](docs/decisions/swifttui-fork.md) prohibits forks, vendored changes and checkout patches.
- [ ] **TUI-UPSTREAM-01 — Prepare GitHub issue drafts later.** Deferred at the user's request. Preserve the two candidate reports and reproduction requirements in the [dedicated follow-up](docs/swifttui-upstream-follow-up.md). Do not prepare/file issues or contact maintainers now.
- [ ] **MENUBAR-01 — Complete the user-run native smoke and energy checks.** Follow the [manual checklist](docs/development.md#manual-macos-smoke-test), including responsibility labels, five-second display, recent workers, coverage, live/static close/reopen, focus and menus. Measure closed-panel cost and inspect App Nap separately. Physical checks remain pending until the user reports them; Computer Use stays disabled.
- [ ] **MENUBAR-03 — Complete targeted accessibility and interaction checks.** Use the [targeted follow-ups](docs/development.md#manual-macos-smoke-test) for diagnosis, detachment, contextual controls and VoiceOver. These are not routine prerequisites for every code edit.
- [ ] **ACTIONS-03 — Complete terminal-focus variants.** Test background/minimized windows, Spaces/full screen, shared-terminal cases and first Automation consent using the [disposable-target checklist](docs/development.md#manual-terminal-focus-check).

### Deferred features

- [ ] **PROBE-01 — Review container totals after CPU-01 acceptance.** [Proposal only](docs/proposals/container-resource-probes.md); implementation needs separate approval. Keep host and guest totals separate, strip environment variables except allowlisted markers, and exclude exec/attach and guest-process inspection.
- [ ] **CAPTURE-01 — Review bounded diagnostic recording after CPU-01.** [Recording remains unapproved](docs/proposals/diagnostic-recording.md). Validate framing, writer ownership, cutoffs, attribution and memory/storage bounds before measuring serialization costs. Default-off means no recorder files, queues or cumulative history; normal monitoring retains bounded rolling memory only.

## Scope and pending decisions

### Temporary feedback intake — 2026-10-17

- [ ] **FEEDBACK-02…13 — Finish process-view usability and keyboard triage.** The [dated evidence and current source dispositions](docs/research/terminal-ui.md#feedback-triage--2026-10-26) preserve each ID and screenshot provenance. Remaining feedback concerns pin symbols and physical German-keyboard scrolling (FEEDBACK-13). Overview improvements do not close process-view defects. `?` help and alternative diagnosis bindings remain ideas, not approved implementation. Use the [TUI workflow check](docs/development.md#manual-tui-workflow-check).

### Execution and authorization boundaries

- Keep 100 ms baseline acquisition, one-second metadata freshness, identity checks and frozen labels. Coverage takes priority over cost; proposed target changes return to the user rather than being adopted silently.
- Distinguish ordinary CLI/TUI, diagnostic launch-policy and native-app results; one diagnostic arm does not authorize host reclassification or a higher scheduling class.
- No new burners, artificial saturation or native churn trials. Earlier bounded short-worker and coalition authorizations were consumed; deterministic in-memory tests remain allowed. New observation mechanisms do not authorize privileged helpers, entitlement/security changes or native probes.
- Analyze new profiles and delete their data and temporary binaries. The earlier permitted aggregate tables may remain local but must not enter Git; no later profile-retention exception is authorized.
- Live messaging/signalling requires disposable authorized targets. Real Codex workload/recipient validation remains a [coverage gap](docs/development.md#validation-coverage), not permission to act on existing sessions.
- Preserve the [child-counter rejection](docs/decisions/exited-descendant-cpu.md), [Codex registry deferral](docs/decisions/codex-session-registry.md) and [menu-bar scope decisions](docs/decisions/menubar-product-scope.md). Interval-supported ownership, historical session-memory peaks and tracing are not approved implementations.

### Existing scope decisions

Optional app icons, a sortable provider column/provider filter, and author credit in `--help` remain separate ideas. Distribution, new platforms/providers, background services, notifications, external plugins and broader terminal/container attribution require separate scope decisions; the [working-model proposal](docs/proposals/agent-working-model.md) is not adopted. Current capabilities belong in [architecture](docs/architecture.md), not a completed-feature log here.
