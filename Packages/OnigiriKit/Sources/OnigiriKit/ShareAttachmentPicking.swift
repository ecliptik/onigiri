import Foundation
import UniformTypeIdentifiers

/// Pure decision logic pulled out of `OnigiriShare/ShareViewController.swift`
/// (health-check audit, 2026-09-14) — the share extension itself has no
/// test target (an `NSItemProvider` isn't something a unit test can build),
/// so the one piece of real conditional logic in its attachment-sniffing
/// moved here, where `OnigiriKitTests` can drive it with plain strings.
public enum ShareAttachmentPicking {
    /// The first CONCRETE image type across every provider's registered
    /// type identifiers, in order — `registeredTypeIdentifiers[i]` is one
    /// provider's own list. A Photos share vends `public.heic` or
    /// `public.jpeg`; a screenshot vends `public.png`. Any of them
    /// CONFORMS to `public.image`, but only the concrete one can actually
    /// be loaded — `public.image` itself is skipped on purpose.
    public static func imageAttachmentIndex(
        registeredTypeIdentifiers: [[String]]
    ) -> (providerIndex: Int, identifier: String)? {
        for (index, identifiers) in registeredTypeIdentifiers.enumerated() {
            for identifier in identifiers {
                guard let type = UTType(identifier), type.conforms(to: .image),
                      type != .image else { continue }
                return (index, identifier)
            }
        }
        return nil
    }
}
