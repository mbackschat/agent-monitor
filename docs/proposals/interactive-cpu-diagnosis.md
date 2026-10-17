# CPU diagnosis in the Mac app and TUI

Status: **approved**, 2026-10-17. Approved by the user for implementation in both interfaces. It reuses the [finite CPU diagnosis contract](../architecture.md#finite-cpu-diagnosis). [Local evidence and limits](../research/existing-solutions.md#interactive-diagnosis-assessment--2026-10-17) distinguish observed code behavior from expected usability benefits.

Recommend an explicit **Diagnose CPU** view in both interfaces. It answers “what consumed the most measured CPU during this investigation?” without changing the live table's latest-interval values. An early contributor remains inspectable after it leaves the final scan. This captures work during a new investigation; it cannot reconstruct a burst that ended before the user started it.

## Required behavior

- Offer **Diagnose CPU** from the native panel and the TUI's `d` key, advertised in its key hints and `guide tui`. Invoking it starts one diagnosis immediately, without confirmation. **Run again** discards the previous result as soon as the new run starts; failure or cancellation does not restore it.
- Put this explanation in the native control's help and TUI key hint, and repeat it in the collecting state: “Measures from now: three one-second waits plus scan time; provider lookup may add up to three seconds per queried provider.” The window begins with a fresh baseline at invocation, never with retained live samples. Each run may invoke a provider CLI after collection, independently of live monitoring's once-a-minute listing cadence.
- Use the existing baseline plus three one-second waits, top ten by measured CPU-seconds, current-user scope excluding this monitor, independent host context, coverage counts and bounded enrichment. No new window, limit, provider recognition or accounting rules.
- Show collecting, completed, failed and cancelled states distinctly. Collection failure shows the existing `collectionFailed` explanation and no partial success result. Missing counters or failed provider lookups remain valid partial results with their diagnostic explanations. Cancellation does not masquerade as failure or measured zero.
- Keep the completed result fixed, with its observation timestamps, until rerun or dismissal. Display CPU-seconds, mean/peak CPU, coverage, exact PID/start identity, latest measured footprint and available attribution evidence. Preserve the shared-daemon and launch/current-session qualifications. Explain `notObservedAtEnrichment` as absence at enrichment, not proof of exit; such rows remain in the ranking.
- Use a scrollable view inside the existing native panel and TUI viewport, with access to full identities and evidence. Reuse presentation explanations and safe text handling. Native controls and accessibility follow native conventions; the TUI uses keyboard navigation.
- Provide Cancel while collecting and Back to the live report. Cancel immediately leaves the collecting state; Back immediately returns to the report. Either requests cancellation without waiting for synchronous reads or subprocess cleanup. Allow only one diagnosis per interface instance; starting another run remains disabled until the active run and any cancellation cleanup finish. Only the current run may publish state; a dismissed, cancelled or superseded run cannot deliver a result into a reopened view.
- Dismissing the native popover, closing its detached window, leaving the TUI diagnosis view or quitting cancels the owned run and discards its result. Native drag detachment that keeps the panel visible preserves the run. Results are in-memory only. Quit drains owned work through the interface's existing shutdown lifecycle.
- Keep ordinary sampling, history, native icon, session totals, thresholds, grouping, pins and live-table selection independent. Diagnosis can start while the live view is frozen or paused and does not resume it; Back restores that same state, or the latest live report if it was not paused. The diagnosis window never feeds live totals or history. Starting diagnosis is unavailable during action review; diagnosis rows have no message, terminate or focus actions. A closed native panel, including static-icon mode, cannot start diagnosis; open the panel first.
- Below the TUI's 40×8 minimum viewport, disable starting or rerunning diagnosis and show the resize hint. An existing run continues; Cancel, Back and quit remain available. Resizing back restores its current state.
- Concurrent monitoring can create helpers inside the measured population. Keep their CPU in totals and ranking, but mark a contributor **Monitor helper** if, during the window, its observed `parentPID` equals this interface's live process PID, or its observed ancestry contains a lifetime with that direct-parent evidence. The monitor stays excluded from scans; its PID cannot be reused while this interface is alive. Retain the flag by exact contributor PID/start identity through the run, never transferring it to a reused PID. Show it beside attribution so inherited agent markers are not mistaken for proof of agent-caused work. Do not infer helper status from executable names, directories or markers. Unobserved or already-reparented helpers may remain unclassified, and other Agent Monitor instances and their helpers may appear as ordinary, unflagged contributors; disclose these limits rather than claim complete overhead exclusion.

The existing [diagnosis result and schema](../../Sources/AgentMonitorPresentation/Resources/diagnosis.schema.json) define the shared data. A result heading could read:

```text
CPU diagnosis · completed at 12:00:03
Window started at invocation · measured 3.2 s · top 10 by CPU-seconds
Host: 210% of 800% (3/3 intervals)
Your measured processes: 122% over window · 3.9 CPU-s
```

The process percentage is `population.windowCPUPercent`, including omitted contributors; the host percentage is its duration-weighted mean. Show the host's valid-interval count even when incomplete, and “No data” when unavailable. When `host.logicalCPUCount` is absent, omit “of N%” and show the shared `hostCapacityChanged` explanation. The figures retain their separate coverage details; their difference is never presented as unattributed CPU. Results disclose that collection and provider lookups add runtime and resource use.

Core computes and carries the flag as `DiagnosisContributor.isMonitorHelper: Bool`; `false` means no helper relation was observed, not proof of independence. Views consume that field rather than reconstructing ancestry. The field stays out of CLI text and JSON encoders, so CLI output and its schema remain unchanged. No subprocess invocation of `agent-monitor` or provider logic belongs in a renderer. Use the approved bounded detached-runtime enrichment so the same evidence does not produce weaker attribution than the live table.

## Alternatives and limits

| Alternative | Assessment |
| --- | --- |
| Lower the live interval to one second | The cheapest option for fresher latest-interval values, already available. It adds sustained sampling work and still drops departed rows; it does not rank cumulative CPU-seconds or retain contributors from a finite investigation. Prefer it when freshness alone is the goal. |
| Change the live table to rolling CPU-seconds ranking | Defer. It changes the meaning of displayed CPU and requires explicit retention, coverage and stale-row rules at variable sampling intervals. Existing scalar history cannot supply per-process contributions. |
| Reuse only the live table's last few snapshots | Defer. Report snapshots lack raw contribution durations, and threshold filtering omits contributors before aggregation. Summing their CPU percentages would be incorrect. |
| Add more help explaining the current live table | Useful guidance, but it cannot preserve a contributor that disappears before inspection. |

The explicit finite view is the smallest complete reuse of the shipped diagnosis. It performs additional scans alongside ordinary monitoring, so its overhead is not established as negligible. Concurrent native reads and declared provider lookups need headless composition checks and owned-workload measurements before making responsiveness or energy claims. The three-second window may still miss short work; no periodic sampler can recover unseen exited processes from these counters.

## Optional and excluded

There are no optional additions in this revision. Automatic reruns, background diagnosis, rolling process history, exports, new settings, actions on historical rows, memory diagnosis, exited-descendant recovery and changes to the live table or icon are excluded. Live usability, keyboard/accessibility delivery and whether this view helps users locate bursts remain unverified.
