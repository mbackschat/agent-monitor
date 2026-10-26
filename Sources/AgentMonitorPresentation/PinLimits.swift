enum PinLimits {
    static let maximumCount = 256
    static let maximumTextBytes = 64 * 1024
    static let refusal = "Pin limit reached · unpin one or all (u)"

    static func admits(count: Int, bytes: Int, adding: Int) -> Bool {
        count < maximumCount && adding <= maximumTextBytes - bytes
    }
}

extension ReportPin {
    var textBytes: Int {
        let identityBytes: Int
        switch id {
        case .process, .group(.unresolved): identityBytes = 0
        case .group(.session(let provider, let id)):
            identityBytes = provider.utf8.count + id.utf8.count
        }
        return label.utf8.count + identityBytes
    }
}

extension ContributorID {
    var pinTextBytes: Int {
        switch self {
        case .session(let provider, let session, let root):
            provider.utf8.count + session.utf8.count + (root?.utf8.count ?? 0)
        case .section, .collapsed, .provider, .executable, .more, .process: 0
        }
    }
}
