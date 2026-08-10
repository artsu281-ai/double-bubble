import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Sheet for editing a profile's name, color, icon, and target app.
struct ProfileSetupView: View {
    @Binding var profile: Profile
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedColor: Color = .blue
    @State private var appURL: URL?
    @State private var appIcon: NSImage?
    @State private var customIcon: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area
            HStack {
                Text("Edit Profile")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Icon preview
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedColor.opacity(0.2))
                                .frame(width: 90, height: 90)

                            if let icon = customIcon ?? appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 40))
                                    .foregroundStyle(selectedColor)
                            }
                        }

                        HStack(spacing: 10) {
                            Button(customIcon == nil ? "Choose Icon…" : "Change Icon…") {
                                pickCustomIcon()
                            }
                            .controlSize(.small)

                            if customIcon != nil {
                                Button("Use App Icon") { clearCustomIcon() }
                                    .controlSize(.small)
                            }
                        }
                    }

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Profile Name", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. Work Account", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Accent Color", systemImage: "paintpalette.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(presetColors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .shadow(color: color.opacity(0.5), radius: selectedColor == color ? 6 : 0)
                                    .scaleEffect(selectedColor == color ? 1.15 : 1.0)
                                    .animation(.spring(response: 0.2), value: selectedColor)
                                    .onTapGesture { selectedColor = color }
                            }

                            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 28, height: 28)
                        }
                    }

                    // App picker
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Target Application", systemImage: "app.badge")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            if let url = appURL {
                                HStack(spacing: 8) {
                                    if let icon = appIcon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                    }
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .lineLimit(1)
                                        .font(.system(size: 13))
                                }
                                .padding(6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                Spacer()

                                Button {
                                    clearApp()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove selected app")
                            } else {
                                Text("No app selected")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 13))

                                Spacer()
                            }

                            Button("Choose…") { pickApp() }
                                .controlSize(.regular)
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 360)
        .onAppear { loadFromProfile() }
    }

    // MARK: - Preset Colors
    private let presetColors: [Color] = [
        Color(hex: "#4F8EF7"), Color(hex: "#34C759"), Color(hex: "#FF9500"),
        Color(hex: "#FF3B30"), Color(hex: "#AF52DE"), Color(hex: "#00C7BE")
    ]

    // MARK: - Actions

    private func loadFromProfile() {
        name = profile.name
        selectedColor = Color(profile.nsColor)
        appURL = profile.targetAppURL
        if let url = appURL {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        if let data = profile.customIconData {
            customIcon = NSImage(data: data)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Select Application"
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            appURL = url
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
            let bookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            profile.targetAppBookmark = bookmark
        }
    }

    private func clearApp() {
        appURL = nil
        appIcon = nil
        profile.targetAppBookmark = nil
    }

    private func pickCustomIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose Icon Image"
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            customIcon = img
            profile.customIconData = resizedPNGData(from: img)
        }
    }

    private func clearCustomIcon() {
        customIcon = nil
        profile.customIconData = nil
    }

    private func resizedPNGData(from image: NSImage, maxDimension: CGFloat = 128) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1)
        newImage.unlockFocus()

        guard let tiff = newImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func save() {
        profile.name = name.isEmpty ? "Profile" : name
        let nsColor = NSColor(selectedColor)
        profile.colorHex = nsColor.hexString
        if let url = appURL {
            let bookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            profile.targetAppBookmark = bookmark
        }
    }
}

// MARK: - Color hex init (SwiftUI)
extension Color {
    init(hex: String) {
        let nsColor = NSColor(hex: hex) ?? .systemBlue
        self.init(nsColor)
    }
}
