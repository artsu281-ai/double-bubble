import Foundation
import os

/// Somewhere for a failure to go.
///
/// Ninety `try?` live in this app, forty of them in `LaunchEngine` alone, and
/// each one turns a failure into nothing at all: a delete that did not happen,
/// a symlink that was not made, a file that was not written, and no trace of
/// it in the interface, in a log, or anywhere else. Most of them are correct
/// to ignore — a missing temporary file is not news. The ones that are not
/// correct to ignore are the destructive ones and the ones that leave an
/// account half-built.
///
/// This does not change what happens; it changes whether anyone can find out
/// what happened. `log stream --predicate 'subsystem == "com.doublebubble.app"'`
/// in Terminal, or Console.app, now shows them.
enum Diagnostics {
    static let launch = Logger(subsystem: "com.doublebubble.app", category: "launch")
    static let storage = Logger(subsystem: "com.doublebubble.app", category: "storage")

    /// Runs something that can fail and says so when it does.
    ///
    /// `what` is written to be readable a week later by someone who has
    /// forgotten this code exists: "removing the copy for account 1a352e71",
    /// not "removeItem".
    @discardableResult
    static func attempt(
        _ what: @autoclosure () -> String,
        log: Logger = storage,
        _ body: () throws -> Void
    ) -> Bool {
        do {
            try body()
            return true
        } catch {
            // Built before handing it to the logger: an autoclosure cannot be
            // captured by the escaping interpolation `Logger` uses.
            let described = what()
            log.error("\(described, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
