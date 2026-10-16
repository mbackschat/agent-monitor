# CPU diagnosis in the Mac app and TUI

Status: **unapproved**, 2026-10-17. Assessment requested after the CLI diagnosis implementation; this proposal does not authorize UI implementation. It reuses the [finite CPU diagnosis contract](../architecture.md#finite-cpu-diagnosis). [Local evidence and limits](../research/existing-solutions.md#interactive-diagnosis-assessment--2026-10-17) distinguish observed code behavior from expected usability benefits.

Recommend an explicit **Diagnose CPU** view in both interfaces. It answers “what consumed the most measured CPU during this investigation?” without changing the live table's latest-interval values. An early contributor remains inspectable after it leaves the final scan. This captures work during a new investigation; it cannot reconstruct a burst that ended before the user started it.

## Required behavior

- Offer **Diagnose CPU** from the native panel and TUI, with an advertised TUI key in its help. Invoking it starts one diagnosis; **Run again** explicitly replaces the result. Only one diagnosis may run per host at a time.
- Use the existing baseline plus three one-second waits, top ten by measured CPU-seconds, current-user scope excluding this monitor, independent host context, coverage counts and bounded enrichment. No new window, limit, provider recognition or accounting rules.
- Show collecting, completed, failed and cancelled states distinctly. Collection failure shows the existing `collectionFailed` explanation and no partial success result. Missing counters or failed provider lookups remain valid partial results with their diagnostic explanations. Cancellation does not masquerade as failure or measured zero.
- Keep the completed result fixed, with its observation timestamps, until rerun or dismissal. Display CPU-seconds, mean/peak CPU, coverage, exact PID/start identity, latest measured footprint and available attribution evidence. Preserve the shared-daemon and launch/current-session qualifications. Explain `notObservedAtEnrichment` as absence at enrichment, not proof of exit; such rows remain in the ranking.
- Use a scrollable view inside the existing native panel and TUI viewport, with access to full identities and evidence. Reuse presentation explanations and safe text handling. Native controls and accessibility follow native conventions; the TUI uses keyboard navigation.
- Provide Cancel while collecting and Back to the live report. Leaving the diagnosis view or closing the host cancels its owned run and discards its state. Late completion must not reopen a dismissed view. Completed results are in-memory only.
- Keep ordinary sampling, history, native icon, session totals, thresholds, grouping, pins and live-table selection independent. Returning to the live report shows its normal current state. The diagnosis window never feeds live totals or history. Starting diagnosis is unavailable during action review; diagnosis rows have no message, terminate or focus actions.

The existing [diagnosis result and schema](../../Sources/AgentMonitorPresentation/Resources/diagnosis.schema.json) define the shared data. A result heading could read:

```text
CPU diagnosis · completed at 12:00:03
Measured window: 3.2 s · top 10 by CPU-seconds
Host: 210% of 800% · your measured processes: 3.9 CPU-s
```

The host and process figures retain their separate coverage details; their difference is never presented as unattributed CPU. Results disclose that collection and provider lookups add runtime and resource use. Views consume the core result; no subprocess invocation of `agent-monitor` or provider logic belongs in a renderer.

## Alternatives and limits

| Alternative | Assessment |
| --- | --- |
| Change the live table to rolling CPU-seconds ranking | Defer. It changes the meaning of displayed CPU and requires explicit retention, coverage and stale-row rules at variable sampling intervals. Existing scalar history cannot supply per-process contributions. |
| Reuse only the live table's last few snapshots | Defer. Report snapshots lack raw contribution durations, and threshold filtering omits contributors before aggregation. Summing their CPU percentages would be incorrect. |
| Add more help explaining the current live table | Useful guidance, but it cannot preserve a contributor that disappears before inspection. |

The explicit finite view is the smallest complete reuse of the shipped diagnosis. It performs additional scans alongside ordinary monitoring, so its overhead is not established as negligible. Concurrent native reads and declared provider lookups need headless composition checks and owned-workload measurements before making responsiveness or energy claims. The three-second window may still miss short work; no periodic sampler can recover unseen exited processes from these counters.

## Optional and excluded

There are no optional additions in this revision. Automatic reruns, background diagnosis, rolling process history, exports, new settings, actions on historical rows, memory diagnosis, exited-descendant recovery and changes to the live table or icon are excluded. Live usability, keyboard/accessibility delivery and whether this view helps users locate bursts remain unverified.
