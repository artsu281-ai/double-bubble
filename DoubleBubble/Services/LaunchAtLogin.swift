import ServiceManagement

/// Thin wrapper around `SMAppService` — starts Double Bubble at login so
/// menu-bar-only usage (window closed, app still tracking accounts) survives
/// a restart without the user remembering to relaunch it by hand.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Registration can fail for an unsigned/ad-hoc build outside
            // /Applications — the toggle just won't stick, nothing to crash.
        }
    }
}
