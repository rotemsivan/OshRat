import Foundation

/// A first guess at a card payment's category from the merchant's name —
/// "SHUFERSAL DEAL" is groceries, "PAZ YELLOW" is fuel — for a shop the
/// user has never logged, where `PaymentPrefill.resolve` has no earlier row
/// to copy a category from. The user's own history always wins: this is only
/// the last resort, and once they log the shop with any category, that is
/// what the next payment there copies.
///
/// Keyed by the **default** categories' names (`SeedData`), which are
/// immutable, so a hint can't point at a category that was renamed away.
/// Common Israeli chains and plain words, in Hebrew and in the Latin
/// spelling card issuers usually send.
enum MerchantCategoryHints {

    /// Category name → keywords, **checked in this order**: the first match
    /// wins, so more specific entries come first ("super pharm" is a
    /// pharmacy before "super" can make it groceries). A one-word keyword
    /// matches the start of any word in the merchant's name ("shufersal" in
    /// "SHUFERSAL DEAL", "aroma" in "AROMA TLV"); a keyword with a space
    /// must appear as that phrase.
    static let table: [(category: String, keywords: [String])] = [
        ("בריאות", [
            "super pharm", "סופר פארם", "be pharm", "pharm", "פארם", "pharmacy", "בית מרקחת",
            "clalit", "כללית", "maccabi", "מכבי", "meuhedet", "מאוחדת", "leumit", "לאומית",
            "optic", "אופטיקה",
        ]),
        ("כלכלת בית", [
            "shufersal", "שופרסל", "rami levy", "רמי לוי", "yochananof", "יוחננוף",
            "victory", "ויקטורי", "osher ad", "אושר עד", "tiv taam", "טיב טעם",
            "yeinot bitan", "יינות ביתן", "carrefour", "קרפור", "hatzi hinam", "חצי חינם",
            "am pm", "mega", "מגה", "super", "סופר", "מכולת", "minimarket", "market", "מרקט",
        ]),
        ("מסעדות ובתי קפה", [
            "aroma", "ארומה", "cofix", "קופיקס", "landwer", "לנדוור", "greg", "גרג",
            "cafe", "caffe", "coffee", "קפה", "starbucks", "roladin", "רולדין",
            "mcdonald", "מקדונלד", "burger", "בורגר", "pizza", "פיצה", "domino", "דומינו",
            "wolt", "וולט", "10bis", "תן ביס", "falafel", "פלאפל", "shawarma", "שווארמה",
            "sushi", "סושי", "restaurant", "מסעדה", "bakery", "מאפייה",
        ]),
        ("הוצאות רכב", [
            "paz", "פז", "sonol", "סונול", "delek", "דלק", "dor alon", "דור אלון",
            "pango", "פנגו", "cellopark", "סלופארק", "parking", "חניה", "חניון",
            "car wash", "שטיפת רכב", "garage", "מוסך",
        ]),
        ("תחבורה ציבורית", [
            "rav kav", "רב קו", "israel railways", "רכבת ישראל", "egged", "אגד",
            "metropoline", "מטרופולין", "gett", "yango", "יאנגו", "taxi", "מונית",
        ]),
        ("אופנה וביגוד", [
            "zara", "זארה", "h m", "castro", "קסטרו", "fox", "פוקס", "renuar", "רנואר",
            "golf", "גולף", "terminal x", "טרמינל איקס", "mango", "מנגו", "bershka",
            "pull bear", "nike", "נייקי", "adidas", "אדידס", "american eagle", "hoodies", "הודיס",
            "foot locker", "shoes", "נעליים",
        ]),
        ("בילויים", [
            "cinema", "סינמה", "yes planet", "יס פלאנט", "eventim", "leaan", "לאן",
        ]),
        ("טיפוח", [
            "barber", "מספרה", "salon", "hair",
        ]),
        ("כושר גופני", [
            "holmes place", "הולמס פלייס", "go active", "גו אקטיב", "gym", "חדר כושר",
        ]),
    ]

    /// The default category name the merchant's name suggests, if any.
    static func categoryName(forMerchant merchant: String) -> String? {
        let folded = HebrewSearch.fold(merchant)
        let words = HebrewSearch.words(ofFolded: folded)
        guard !words.isEmpty else { return nil }
        for entry in table {
            for keyword in entry.keywords {
                let key = HebrewSearch.fold(keyword)
                let matches = key.contains(" ")
                    ? " \(folded) ".contains(" \(key) ")
                    : words.contains { $0.hasPrefix(key) }
                if matches { return entry.category }
            }
        }
        return nil
    }
}
