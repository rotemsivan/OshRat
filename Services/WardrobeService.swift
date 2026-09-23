import Foundation
import SwiftData

/// Reads and changes what the user's rat is wearing.
enum WardrobeService {

    /// The config row, created on first use. Resolves to the oldest row if
    /// several exist, matching `ProgressService.progress(in:)`.
    static func config(in context: ModelContext) -> MascotConfig {
        var descriptor = FetchDescriptor<MascotConfig>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = MascotConfig()
        context.insert(created)
        return created
    }

    /// Put `item` on, replacing whatever was in its slot. Refuses an item the
    /// user's level hasn't unlocked — the wardrobe never offers one, but the
    /// rule belongs here rather than in a view.
    static func equip(_ item: WardrobeItem, atLevel level: Int, in context: ModelContext) {
        guard item.isUnlocked(atLevel: level) else { return }
        config(in: context).setEquippedID(item.id, for: item.slot)
        try? context.save()
    }

    /// Take off whatever is in `slot`.
    static func unequip(_ slot: WardrobeSlot, in context: ModelContext) {
        config(in: context).setEquippedID(nil, for: slot)
        try? context.save()
    }
}
