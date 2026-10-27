/// Capabilities withheld by the no-Internet runtime contract in CLAUDE.md.
public enum ProviderRuntimeAvailability {
    public static let sessionListingUnavailableReason =
        "Live session listings and session names are unavailable because provider helpers cannot be guaranteed offline."
    public static let messagingUnavailableReason =
        "Messaging is unavailable because provider helpers cannot be guaranteed offline."
}
