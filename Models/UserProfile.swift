import Foundation
import SwiftData

/// The person using the app. There's normally just one of these.
/// Holds the personal details collected during onboarding.
///
/// Note: every stored property has a default value. That keeps the model
/// CloudKit-compatible, so enabling iCloud sync later needs almost no rework.
@Model
final class UserProfile {
    var name: String = ""
    var profession: String = ""
    /// Free-text aspirations the user writes during setup (e.g. "לקנות דירה").
    var goalsText: String = ""
    /// Default ISO currency code for new items, e.g. "ILS".
    var preferredCurrencyCode: String = "ILS"
    var createdAt: Date = Date.now

    init(
        name: String = "",
        profession: String = "",
        goalsText: String = "",
        preferredCurrencyCode: String = "ILS"
    ) {
        self.name = name
        self.profession = profession
        self.goalsText = goalsText
        self.preferredCurrencyCode = preferredCurrencyCode
        self.createdAt = .now
    }
}
