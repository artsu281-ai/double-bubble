import Foundation
import AppKit

struct AppInstance: Identifiable {
    let id: UUID
    let accountId: UUID
    let pid: pid_t
    /// For bundleCopy: path to copied .app
    /// For electron/jetbrains/configDir: path to isolated data directory
    let bundleCopyURL: URL
    let launchedAt: Date
    let strategy: LaunchStrategy

    /// Version of the source app at the moment this instance started.
    ///
    /// A copy is rebuilt from the original on every launch, so a *new* launch
    /// always picks up an update — but a process already running keeps the
    /// build it started with. Recording it lets the UI notice when the
    /// original has moved on and say so, instead of leaving someone on a
    /// stale build without a word.
    ///
    /// `nil` when unknown — notably for instances adopted after Double Bubble
    /// itself restarted, where guessing would risk a false alarm.
    var launchedVersion: String?
}
