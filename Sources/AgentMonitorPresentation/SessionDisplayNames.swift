import AgentMonitorCore

/// Provider-listed names are display context, never grouping or accounting keys.
struct SessionDisplayNames {
    private struct Key: Hashable {
        let provider: String
        let session: String
    }
    private struct Entry {
        var scan: UInt64
        var names: Set<String>
    }
    private var entries: [Key: Entry] = [:]

    init(records: some Sequence<RecentWorkerRecord>) {
        for record in records {
            let owner = record.category.owner
            guard owner.resolution == .candidate, let provider = owner.provider,
                let session = owner.sessionID, let name = record.sessionName
            else { continue }
            let key = Key(provider: provider.rawValue, session: session)
            if entries[key].map({ $0.scan < record.lastScan }) ?? true {
                entries[key] = Entry(scan: record.lastScan, names: [name])
            } else if entries[key]?.scan == record.lastScan {
                entries[key]?.names.insert(name)
            }
        }
    }

    func name(provider: String, session: String) -> String? {
        guard let entry = entries[Key(provider: provider, session: session)], entry.names.count == 1 else {
            return nil
        }
        return entry.names.first
    }
}
