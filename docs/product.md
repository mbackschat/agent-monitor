# Product goal and information contract

## The question the product must answer

**Which coding agents, sessions and processes are consuming CPU or memory, and in which working directories?** This is the number-one product goal. Usually several contributors matter, so users need a table that lets them compare those relationships. Agent Monitor is not another general-purpose top clone. Measurement, attribution, ranking, labels, grouping, disclosure and actions must all help answer this question.

Monitoring must work transparently with already-running agents. Requiring workloads to launch through Agent Monitor or adopt cooperative worker hooks cannot satisfy the core coverage requirement. New observation mechanisms still need a supported deployment and permission model; this requirement does not authorize privileged helpers, security changes or native experiments.

Short-worker precision is especially important while the user inspects the UI: discover workers promptly, keep their measured CPU and memory contribution visible under the responsible session, and disclose what was missed. Older workers may become bounded aggregate summaries with qualified precision rather than indefinitely retained rows. This prioritizes inspection without waiving general transparent coverage, independent display cadence, attribution correctness or the prohibition on inventing unseen CPU.

The experience should be a **clear, actionable resource overview**, usable while the machine is busy and the user is under pressure. “Dashboard” and “cockpit” describe the desired orientation, not a required screen layout. iStat Menus and htop/btop inform familiar controls and resource displays; agent/session responsibility defines this product's information model.

## Information that belongs together

| Information | Required meaning |
| --- | --- |
| Agent | Recognised provider, such as Claude or Codex; preserve unknown or conflicting evidence. |
| Session | A verified human-readable session name when available, with stable provider/session identity. Otherwise show the provider and an abbreviated session ID, with the full ID on demand. Never fabricate a session name from a directory. |
| Working directory | The workload's observed CWD, with a compact distinguishable path and access to the full path. Several directories in one session must remain distinguishable; a shared runtime's launch directory is not the workload CWD. |
| Process | The observed executable basename, such as `rustc`, `java` or `node`, associated visibly with its agent/session and CWD. Aggregate repeated workers when useful; exact lifetimes remain inspectable. |
| Contribution | Comparable CPU and current-memory values with units. Distinguish recent CPU from current load and sampled memory maxima from current memory. Rank children consistently with the selected CPU/memory ordering. |
| Relevant detail and actions | Disclose arguments, full paths, exact identities and evidence on demand. Reach the relevant verified process/session action without losing ownership context. Historical aggregates are not executable action targets. |

The main comparison must expose agent/session, workload directory, executable and resource contribution together without requiring users to open every process. A directory summary such as “Multiple directories” must not replace or truncate away session identity. Expansion must help find contributing executables and their workloads, rather than expose an undifferentiated list of PIDs. The precise row unit and use of columns or contextual subrows must be reviewed across Mac and TUI before redesign; a fixed hierarchy or separate Explorer window is not prescribed here.

Use the [accepted ledger with activity lanes](architecture.md#constrained-overview-presentation): aligned comparable values, readable identity, full-width workload context and structured expansion. Graphs must preserve real retained timing and expose their common scale; a busy-looking invented curve is worse than an honest gap. Disclosure should contain structured information, not hidden paragraphs. Explanations belong in tooltips/help; material measurement gaps remain visible beside the numbers they qualify. Preserve readable values and identity at narrow widths, with deliberate disclosure for secondary detail. Compactness is useful only while the question remains answerable.

## Truthfulness and retention

Coverage and attribution correctness are necessary to answer the question. Do not improve apparent clarity by omitting measured CPU, assigning unknown work to a session, treating CWD as ownership evidence, or hiding memory-heavy/short-lived contributors. Totals remain independent of display filters. Quantified remainders and visible reduced-detail/time-range disclosures preserve orientation under pressure. The [accounting contract](architecture.md#resource-visibility-requirements) owns these semantics; the product goal does not relax them.

**Diagnostic recording is off by default.** Normal monitoring keeps only bounded working state and rolling in-memory history; it does not create a process-data archive on disk or accumulate an unbounded in-memory log. Detailed recent activity and the longer scalar chart have different bounded ranges. Pause may retain a bounded inspection snapshot; it does not start a recording. The separate [recording proposal](proposals/diagnostic-recording.md) requires explicit opt-in, including separate consent to persist full arguments. Explicit JSONL output or user exports are distinct from automatic recording.

## Acceptance and current gaps

This is the intended information contract, not a claim that the present interface meets it. Overview session rows now lead with provider and short session ID, and contributors pair the executable with its frozen workload directory; process-view group headings follow the same identity-first rule, and both interfaces offer explicit process-argument inspection. Production uses provider/ID labels from available local evidence; provider-listed names are unavailable under the [offline runtime contract](architecture.md#offline-runtime). The [architecture](architecture.md#product-experience) describes current behavior; [UX-01](../PLAN.md#resource-accounting-priority) owns the redesign review and implementation gaps. If a verified name is supplied by a supported source, it is display context bound to the verified runtime lifetime and exact provider/session ID. It never changes ownership, grouping or historical CPU. Acquiring names from new sources is a separate evidence/privacy decision, not permission to read transcripts or query new provider endpoints.

A useful review must demonstrate several concurrent CPU and memory contributors; two sessions in one directory; one session in several directories; repeated `java`/`rustc` workers; recent departed work; unknown ownership; and missing measurements. The user must be able to identify the responsible agent/session, CWD and executable, compare contributions, then inspect arguments or reach a safe action. Assess both the native panel and narrow/wide TUI. Correct totals or attractive graphics alone do not satisfy this acceptance test.
