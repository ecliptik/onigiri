import Foundation

/// The 2.1.3 correlation-write rule, isolated where tests can reach it
/// (the macOS test host has no HealthKit): HealthKit rejects an ENTIRE
/// food correlation when any single sample's type isn't write-
/// authorized, so a scanned food's rich nutrients — types the user
/// never granted — would silently fail the whole log. A nutrient row
/// is therefore written only when it has a positive value AND its type
/// is shareable. The kcal row is exempt and always writes: a denied
/// energy type fails loudly and Settings/Today surface it via
/// `sharingDenied()`.
public enum CorrelationWritePolicy {
    /// `isWriteAuthorized` is an autoclosure so the (potentially
    /// store-touching) probe only runs for rows that carry a value.
    public static func includes(
        value: Double?,
        isWriteAuthorized: @autoclosure () -> Bool
    ) -> Bool {
        guard let value, value > 0 else { return false }
        return isWriteAuthorized()
    }
}
