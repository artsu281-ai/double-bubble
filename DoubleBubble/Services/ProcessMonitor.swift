import Foundation
import AppKit
import Combine

// MARK: - ProcessMonitor
//
// Tracks running state of launched AppInstances using three methods:
//   1. NSWorkspace notifications — instant, zero-CPU (for GUI apps via NSWorkspace)
//   2. Process.terminationHandler — instant (for binaries via Process)
//   3. Fallback polling every 5s using kill(pid, 0) for edge cases
//
// Thread-safe: all @Published mutations go through main queue.

final class ProcessMonitor: ObservableObject {

    static let shared = ProcessMonitor()

    @Published private(set) var runningPIDs: Set<pid_t> = []

    private var cancellables = Set<AnyCancellable>()

    /// Serializes access to trackedProcesses dictionary
    private let queue = DispatchQueue(label: "com.doublebubble.processmonitor", qos: .userInitiated)
    private var _trackedProcesses: [pid_t: Process] = [:]

    private var pollTimer: Timer?

    private init() {
        setupWorkspaceObservers()
        startFallbackPoller()
    }

    // MARK: - Register / Unregister

    /// Unconditionally async made `runningPIDs` lag one run-loop turn behind
    /// callers already on the main thread — which is exactly the thread
    /// `AppLibrary` reattaches previously-running accounts from at launch.
    /// It would adopt an instance, register its pid here, and in the same
    /// synchronous pass subscribe a "drop anything not in `runningPIDs`"
    /// cleanup — which ran against the pre-insert snapshot, since the insert
    /// was still sitting in the queue, and dropped the account it had just
    /// found. Reported as: Double Bubble relaunched, a real account was still
    /// running, and it showed as closed — which then let Open launch a
    /// second copy right on top of it. Applying the mutation immediately when
    /// already on main removes the gap; still hopping over when called from
    /// elsewhere keeps every other caller exactly as safe as before.
    private func mutate(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    /// Register a GUI app launched via NSWorkspace
    func registerApp(pid: pid_t) {
        mutate { if !self.runningPIDs.contains(pid) { self.runningPIDs.insert(pid) } }
    }

    /// Register a Process launched directly (Electron binary, JetBrains, etc.)
    /// Safe to call from any thread.
    func registerProcess(_ process: Process, pid: pid_t) {
        mutate { self.runningPIDs.insert(pid) }
        queue.async {
            self._trackedProcesses[pid] = process
        }
        // terminationHandler fires on a background thread
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.mutate { self.runningPIDs.remove(pid) }
            self.queue.async {
                self._trackedProcesses.removeValue(forKey: pid)
            }
        }
    }

    func unregister(pid: pid_t) {
        mutate { self.runningPIDs.remove(pid) }
        queue.async {
            self._trackedProcesses.removeValue(forKey: pid)
        }
    }

    func isRunning(pid: pid_t) -> Bool {
        runningPIDs.contains(pid)
    }

    // MARK: - NSWorkspace Notifications (instant for GUI apps)

    private func setupWorkspaceObservers() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                // Every application on the machine quitting arrives here, and
                // `@Published` republishes on any touch of the setter whether
                // the value changed or not — so closing an unrelated window
                // was invalidating every view watching this. Ask first.
                guard let self, self.runningPIDs.contains(app.processIdentifier) else { return }
                self.runningPIDs.remove(app.processIdentifier)
            }
            .store(in: &cancellables)
    }

    // MARK: - Fallback Poller (5s, for edge cases)

    private func startFallbackPoller() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pids = self.runningPIDs // snapshot
            var stale: [pid_t] = []
            for pid in pids {
                // kill(pid, 0) returns 0 if process exists, -1 if not
                if kill(pid, 0) != 0 {
                    stale.append(pid)
                }
            }
            if !stale.isEmpty {
                DispatchQueue.main.async {
                    stale.forEach { self.runningPIDs.remove($0) }
                }
            }
        }
    }
}
