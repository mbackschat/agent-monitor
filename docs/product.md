# Product goal and information contract

## The question the product must answer

**Which coding agents, sessions and processes are consuming CPU or memory, and in which working directories?** This is the number-one product goal. Usually several contributors matter, so users need a table that lets them compare those relationships. Agent Monitor is not another general-purpose top clone. Measurement, attribution, ranking, labels, grouping, disclosure and actions must all help answer this question.

### Transparent coverage

Monitoring must work transparently with already-running agents. Requiring workloads to launch through Agent Monitor or adopt cooperative worker hooks cannot satisfy the core coverage requirement. New observation mechanisms still need a supported deployment and permission model; this requirement does not authorize privileged helpers, security changes or native experiments.

### Short-lived workers

Short-worker precision is especially important while the user inspects the UI: discover workers promptly, keep their measured CPU and memory contribution visible under the responsible session, and disclose what was missed. Older workers may become bounded aggregate summaries with qualified precision rather than indefinitely retained rows. This prioritizes inspection without waiving general transparent coverage, independent display cadence, attribution correctness or the prohibition on inventing unseen CPU.

### Orientation under load

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

### Present the relationship, not just the fields

Users must be able to compare agent/session, workload directory, executable and contribution without opening every process:

- Keep session identity visible beside directory context; “Multiple directories” cannot replace or truncate it away.
- Make expansion reveal contributing executables and workloads, rather than an undifferentiated PID list.
- Review row units, columns and contextual subrows across Mac and TUI before redesigning them. This contract does not prescribe a fixed hierarchy or separate Explorer window.

Use the [accepted ledger with activity lanes](architecture.md#constrained-overview-presentation): aligned values, readable identity, full-width workload context and structured expansion.

| Presentation requirement | Acceptance rule |
| --- | --- |
| Graphs | Preserve real retained timing and expose a common scale. Show an honest gap rather than inventing activity. |
| Disclosure | Reveal structured detail, not hidden paragraphs. Put explanations in concise tooltips or Help. |
| Measurement limits | Keep material gaps visible beside the numbers they qualify. |
| Narrow layouts | Preserve readable identity and values; disclose secondary detail deliberately. Compactness must not obscure responsibility. |

## Truthfulness and retention

Coverage and attribution correctness are necessary to answer the question. Do not improve apparent clarity by omitting measured CPU, assigning unknown work to a session, treating CWD as ownership evidence, or hiding memory-heavy/short-lived contributors. Totals remain independent of display filters. Quantified remainders and visible reduced-detail/time-range disclosures preserve orientation under pressure. The [accounting contract](architecture.md#resource-visibility-requirements) owns these semantics; the product goal does not relax them.

### Keep normal monitoring bounded

**Diagnostic recording is off by default.** Normal monitoring keeps only bounded working state and rolling in-memory history; it does not create a process-data archive on disk or accumulate an unbounded in-memory log. Detailed recent activity and the longer scalar chart have different bounded ranges. Pause may retain a bounded inspection snapshot; it does not start a recording. The separate [recording proposal](proposals/diagnostic-recording.md) requires explicit opt-in, including separate consent to persist full arguments. Explicit JSONL output or user exports are distinct from automatic recording.

## Acceptance and current gaps

This is the intended contract, not a claim of complete compliance. The [architecture](architecture.md#product-experience) describes current behavior; [UX-01](../PLAN.md#resource-accounting-priority) owns the redesign review and implementation gaps.

Current overview and process-group headings lead with provider/session identity. Contributors pair an executable with its frozen workload directory, and both interfaces offer explicit argument inspection. Production labels use available local provider/ID evidence; provider-listed names are unavailable under the [offline runtime contract](architecture.md#offline-runtime).

A verified name from a supported source is display context bound to the verified runtime lifetime and exact provider/session ID. It never changes ownership, grouping or historical CPU. Adding a name source requires a separate evidence/privacy decision; this contract does not authorize transcript reads or new provider endpoints.

### Demonstrate the full workflow

Review the native panel and both narrow and wide TUI layouts with:

- Several concurrent CPU and memory contributors.
- Two sessions in one directory, and one session spanning several directories.
- Repeated `java` or `rustc` workers and recent departed work.
- Unknown ownership and missing measurements.

In each case, the user must identify the agent/session, CWD and executable, compare contributions, and inspect arguments or reach a safe action. Correct totals or attractive graphics alone do not satisfy acceptance.
