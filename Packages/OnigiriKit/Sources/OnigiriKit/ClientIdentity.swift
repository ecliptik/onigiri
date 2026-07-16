import Foundation

/// One User-Agent for every outbound client. Open Food Facts' API
/// etiquette asks for app/version plus a contact — the public repo is
/// both. Reads the host bundle so the app, widgets, and watch all
/// report their real version instead of a hardcoded one going stale.
enum ClientIdentity {
    static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "Onigiri/\(version) (+https://github.com/ecliptik/onigiri)"
    }()
}
