import Foundation

/// The URL the quick-add widget opens and `HomeView` answers — defined once
/// here and compiled into both targets, so the two can't drift apart.
///
/// The scheme comes from the build (`APP_URL_SCHEME`, surfaced through each
/// target's Info.plist as `OshRatURLScheme`): the dev and release apps each
/// own one, so a widget always opens the app it shipped with rather than
/// whichever one iOS picks for a shared scheme.
enum DeepLink {
    static var scheme: String {
        Bundle.main.object(forInfoDictionaryKey: "OshRatURLScheme") as? String ?? "oshrat"
    }

    private static let newTransactionHost = "new-transaction"

    /// `oshrat://new-transaction` (`oshrat-dev://` in a dev build).
    static var newTransaction: URL? {
        URL(string: "\(scheme)://\(newTransactionHost)")
    }

    static func isNewTransaction(_ url: URL) -> Bool {
        url.scheme == scheme && url.host() == newTransactionHost
    }
}
