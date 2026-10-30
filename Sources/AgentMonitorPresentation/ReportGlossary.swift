import AgentMonitorCore

public enum ReportGlossary {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let definition: String
    }

    public static let otherObservedWork = Entry(
        id: "other-observed-work", title: "Other observed work",
        definition:
            "Summary groups for measured work outside the main session list. They keep additional sessions, uncertain ownership, shared runtimes and older activity visible. These are groups, not extra agents or system-wide usage. They can contain both currently observed and past processes. Expand a group to see its members; its CPU and memory are already included in the overview totals."
    )

    public static func contributorGroup(_ section: ContributorSection) -> Entry {
        let definition =
            switch section {
            case .recent:
                "Sessions outside the main list that used CPU recently, had notable memory use, or were previously in the main list. Recent does not mean stopped: these sessions can still have running processes. Expand to see the sessions and their workloads."
            case .remainder:
                "Additional sessions outside the main list that do not qualify for Recent contributors. They are grouped to keep the overview compact, not discarded or assumed idle. Expand to see them; their measured CPU and current memory remain included in totals."
            case .uncertain:
                "Observed work that cannot be assigned confidently to one exact agent session. Evidence may be missing or conflicting. Its resource use stays visible here rather than being guessed into a session. Expand to inspect the processes and available ownership evidence."
            case .shared:
                "Agent runtime processes that are not assigned to one exact session. Their resource use is counted once here, rather than charged to an arbitrary session. Expand to see the runtimes. This does not mean all shared macOS processes."
            case .released:
                "Measured older work whose individual process identities or directories have been discarded to bound retained history. Aggregate CPU and count ranges remain, but exact process inspection may no longer be possible. Historical memory is not current memory. Open Details to see the retained range and evidence."
            }
        return Entry(id: "group-" + section.rawValue, title: section.rawValue, definition: definition)
    }

    private static let contributorGroups: [Entry] =
        [otherObservedWork]
        + [ContributorSection.recent, .remainder, .uncertain, .shared, .released].map(contributorGroup)

    public static let entries: [Entry] =
        [
            Entry(
                id: "processes", title: "Processes / Procs",
                definition:
                    "Distinct process lifetimes (PID plus start time) associated with this row in the displayed latest scan, including agent runtimes where applicable. In the Mac contributor table, the dot marks currently observed processes; the smaller archive box marks past processes. Counts above 99 display as 99+; hover for exact numbers. A group can contain both. Hiding past rows leaves their measured contribution in totals. While paused, this is the displayed sample, not the machine now. Recent workers and runtime counts overlap with this count; do not add them together. — means current presence is unavailable."
            )
        ] + contributorGroups + [
            Entry(
                id: "process-identifiers", title: "PID / #processes",
                definition:
                    "In the process view, PID identifies an individual process; #N is a session group's distinct contributor lifetimes in the displayed CPU window, including filtered members and retained processes no longer observed. This group count covers the display window; Processes / Procs covers the latest displayed sample. ├─ and └─ connect child processes to their session group; i opens process inspection."
            ),
            Entry(
                id: "cpu", title: "CPU",
                definition:
                    "Measured CPU-seconds divided by the actual display-window duration, shown as a percentage. 100% means one logical core; parallel work can exceed 100%. Includes measured contributors that are no longer observed, not only processes present in the latest scan. — means no valid measurement, not zero CPU. In process-group totals, ~ marks a partial total with missing measurements."
            ),
            Entry(
                id: "activity", title: "Activity lanes",
                definition:
                    "CPU averages over whole retained intervals, using one fixed display range for every row. Hardware chooses the default once: performance plus super cores × 100%, falling back to all logical CPUs when core types are unknown. 100% means one CPU-second per elapsed second, not computing-power saturation. View options or b selects a manual range; activity never rescales it. Equal-width bars run oldest to newest; each bar represents one interval, even when durations differ. Empty spans (terminal dots) are unmeasured, not idle; a baseline is measured zero. Shaded spans or ~ spans have incomplete observations or reduced identity detail. Chart tooltips on Mac and the caption in TUI give the retained range and interval count and flag unequal durations; coalesced or crossing intervals cannot reveal activity inside that span. An orange cap or terminal ↑ marks values above the fixed ceiling; details retain each interval’s actual percentage, CPU seconds and duration. Memory beside the lane is current, not historical."
            ),
            Entry(
                id: "memory", title: "Memory",
                definition:
                    "Sum of readable memory footprints for processes present in the displayed latest scan. MB and GB are decimal (1,000,000 and 1,000,000,000 bytes). ≥ marks a lower bound with missing readings; process-group totals use ~ for partial measurements. This is current sampled memory, not a historical peak."
            ),
            Entry(
                id: "recent-cpu", title: "Recent CPU",
                definition:
                    "Measured CPU-seconds in the actual retained recent range shown above the table. One CPU-second is one core busy for one second. This cumulative contribution differs from display-window CPU % and the 10-minute or one-hour scalar chart."
            ),
            Entry(
                id: "workers", title: "Recent workers",
                definition:
                    "Distinct observed worker lifetimes in the retained recent range, excluding recognised agent runtimes. Includes workers still present and workers no longer observed. A range marks released identity detail; these populations overlap with the latest process count."
            ),
            Entry(
                id: "departed", title: "No longer observed / past",
                definition:
                    "Retained processes absent from the displayed final scan. Absence is not confirmed exit: a process may have become unreadable. A still-observed process whose ownership changes is recorded separately as a membership change. Its measured CPU remains in the applicable window; old memory is not counted as current."
            ),
            Entry(
                id: "runtimes", title: "Agent runtimes",
                definition:
                    "Observed lifetimes recognised by an attribution adapter as agent runtimes. They are separate from the worker count and may also be in the latest process count. Shared runtimes are counted once without assigning their load to an arbitrary session."
            ),
            Entry(
                id: "filters", title: "Filtered members",
                definition:
                    "Observed members outside the selected CPU or memory display thresholds. Filters change inspection rows, not observed session totals or retained measured contribution."
            ),
            Entry(
                id: "ownership", title: "Point candidates / unresolved / changed",
                definition:
                    "Session associations use observed point evidence, not proof of ownership throughout a CPU interval. Unresolved or conflicting work stays explicit. Changed marks a last-observed label that does not describe all CPU in the window. A working directory supplies workload context, not ownership proof."
            ),
            Entry(
                id: "coverage", title: "Coverage / missing data",
                definition:
                    "Observed totals are not guaranteed complete. Polling can miss entire short-lived workers and CPU after a final reading. Failed reads leave CPU, memory and ownership unknown. Diagnostics distinguishes failures, exits before reading, overruns, exclusions and released detail; a clear status does not establish complete coverage."
            ),
            Entry(
                id: "history", title: "History / sampled maximum",
                definition:
                    "The scalar chart retains bounded peak buckets over 10 minutes or one hour; it is separate from detailed recent process history. A sampled memory maximum is the largest retained reading, not current memory. A kernel task peak has an unverified epoch and may predate the displayed range."
            ),
            Entry(
                id: "pause", title: "Pause / retention",
                definition:
                    "Pause freezes the displayed report and history while collection continues. Resume shows the latest data. Normal monitoring retains bounded rolling data in memory; it does not automatically record process data to disk."
            ),
            Entry(
                id: "provider-availability", title: "Provider capability limits",
                definition: ProviderRuntimeAvailability.sessionListingUnavailableReason + " "
                    + ProviderRuntimeAvailability.messagingUnavailableReason),
        ]
}
