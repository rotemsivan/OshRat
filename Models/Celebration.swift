import Foundation

/// Something worth a toast: a level reached, a patch unlocked, or a batch of
/// patches unlocked at once.
///
/// Queued on `UserProgress.pendingCelebrations` as strings (`level:12`,
/// `achievement:log-100`, `achievements:10`) rather than as a Codable enum
/// attribute — the same reason `Account.depositKindRaw` is a `String`: a
/// Codable attribute added to a model that already has rows can trap on read,
/// where a defaulted `[String]` migrates silently. The prefixes are persisted,
/// so don't rename them.
enum Celebration: Hashable {
    case levelUp(Int)
    case achievement(id: String)
    /// Several patches at once — the first launch after achievements shipped,
    /// or a demo deploy. One toast for the lot instead of one each.
    case achievementBatch(count: Int)

    var rawValue: String {
        switch self {
        case .levelUp(let level):            return "level:\(level)"
        case .achievement(let id):           return "achievement:\(id)"
        case .achievementBatch(let count):   return "achievements:\(count)"
        }
    }

    /// `nil` for anything unparseable — a queue entry from a future build is
    /// skipped rather than crashing the toast.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "level":
            guard let level = Int(parts[1]) else { return nil }
            self = .levelUp(level)
        case "achievement":
            guard !parts[1].isEmpty else { return nil }
            self = .achievement(id: parts[1])
        case "achievements":
            guard let count = Int(parts[1]) else { return nil }
            self = .achievementBatch(count: count)
        default:
            return nil
        }
    }
}
