import Foundation

/// One root rule for live grouping and frozen history; see architecture's grouping contract.
public struct SessionCorroboration: Sendable {
    private struct Root: Hashable, Sendable {
        let provider: AgentProvider
        let session: String
        let runtime: ProcessIdentity
    }
    private let roots: Set<Root>

    public init(_ rows: [HeavyProcess]) {
        roots = Set(
            rows.compactMap { row in
                let owner = row.attribution
                guard Self.isExact(owner), let provider = owner.provider, let session = owner.threadID,
                    owner.rootSessionID == session, let runtime = owner.runtime, owner.context != .unverified
                else { return nil }
                return Root(provider: provider, session: session, runtime: runtime)
            })
    }

    public func root(for owner: Attribution) -> String? {
        guard Self.isExact(owner), let provider = owner.provider, let root = owner.rootSessionID,
            let runtime = owner.runtime, owner.context != .unverified,
            roots.contains(Root(provider: provider, session: root, runtime: runtime))
        else { return nil }
        return root
    }

    /// Exact evidence that also names provider and session, the precondition for session-level identity.
    public static func isExactSession(_ owner: Attribution) -> Bool {
        isExact(owner) && owner.provider != nil && owner.threadID != nil
    }

    public static func isExact(_ owner: Attribution) -> Bool {
        switch owner.evidence {
        case .marker, .inheritedMarker, .writerLock: true
        case .unknown, .ambiguous, .runtimeOnly: false
        }
    }
}
