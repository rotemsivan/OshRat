import WidgetKit
import SwiftUI

/// Entry point of the widget extension. A `WidgetBundle` can host several
/// widgets later (e.g. a budget-progress widget); for now it exposes just
/// the quick-add shortcut.
@main
struct OshRatWidgetBundle: WidgetBundle {
    var body: some Widget {
        NewTransactionWidget()
    }
}
