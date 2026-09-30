import Foundation

#if DEBUG
/// The DEBUG command-line hooks — `-demoScenario saver`, `-demoTab analytics`,
/// `-hideAdmin` and the rest (listed in `OshRatApp.applyDemoLaunchArguments`
/// and CLAUDE.md). One parser, so each hook doesn't re-implement the
/// "flag followed by its value" index dance.
enum LaunchArguments {
    static func contains(_ flag: String) -> Bool {
        CommandLine.arguments.contains(flag)
    }

    /// The argument right after `flag` (`-demoTab analytics` → `"analytics"`),
    /// or `nil` when the flag is absent or last.
    static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}
#endif
