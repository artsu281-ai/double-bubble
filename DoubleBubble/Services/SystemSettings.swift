import AppKit

/// Deep links into the two System Settings panes a copy-based account can end
/// up needing: macOS ties Screen Recording and Accessibility grants to the
/// exact signed copy Double Bubble made for that account, not to the app in
/// general, so there is no single place these live — every account with its
/// own copy may need its own grant. These links save a search through System
/// Settings; they don't (and can't) flip the switch themselves.
enum SystemSettingsPane {
    case screenRecording
    case accessibility

    private var urlString: String {
        switch self {
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }

    func open() {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
