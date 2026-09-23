import Foundation

/// Which rat opened the wardrobe — the id its zoom transition grows out of.
///
/// The wardrobe zooms from whichever rat the user tapped (the dashboard's
/// greeting or the profile picture), so it needs to know which one. A
/// level-up toast has no rat to grow from, so it opens with no source.
enum WardrobeEntryPoint: Hashable {
    case greeting
    case profilePicture
    case toast
}
