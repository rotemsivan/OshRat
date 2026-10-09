import AppIntents
import ExtensionFoundation

/// The App Intents extension: a small process the system starts to run
/// `LogPaymentIntent` when the app isn't running — the usual case at the
/// till. It has no SwiftUI app, no store and no iCloud, so a cold start is
/// cheap; cold-launching the whole app there sometimes ran out of the time
/// Shortcuts allows. The intent is the same source file the app compiles
/// (see `LogPaymentIntent`); this target also compiles `PaymentPrefill`,
/// `PaymentInbox` and `PaymentNotification`, and nothing else.
@main
struct OshRatIntentsExtension: AppIntentsExtension {}
