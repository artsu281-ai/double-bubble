import AppKit

/// The "pick an .app" panel, in one place.
///
/// It used to be built inline in three different views, each with its own
/// title and its own idea of where to start. That is a small thing until one
/// of them is the repair flow, where starting somewhere other than
/// `/Applications` is the difference between one click and a hunt.
enum AppChooser {

    @MainActor
    static func pickApplication(title: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title ?? L("Choose an Application")
        panel.prompt = L("Choose")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
