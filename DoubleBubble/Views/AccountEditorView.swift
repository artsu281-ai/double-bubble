import SwiftUI
import AppKit

/// Sheet for renaming an account and picking its identity color.
struct AccountEditorView: View {
    let account: Account
    /// Hex colors already taken by this account's siblings — used to flag a
    /// pick that would make two accounts of the same app indistinguishable.
    var usedColors: Set<String> = []
    var onSave: (Account) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var color: Color = .blue
    @State private var iconData: Data?
    @State private var usesDefaultProfile = false

    private var presets: [Color] { Account.presetColors.map(Color.init(hex:)) }

    private var colorIsTaken: Bool {
        usedColors.contains(NSColor(color).hexString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Account")
                .font(.cardTitle)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Form {
                LabeledContent("Picture") {
                    HStack(spacing: 10) {
                        preview

                        VStack(alignment: .leading, spacing: 4) {
                            Button(iconData == nil ? "Choose…" : "Replace…") {
                                if let picked = AccountIcon.pickFromDisk() { iconData = picked }
                            }
                            if iconData != nil {
                                Button("Use Initial Instead") { iconData = nil }
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                LabeledContent("Color") {
                    HStack(spacing: 10) {
                        ForEach(presets, id: \.self) { preset in
                            Circle()
                                .fill(preset)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.primary.opacity(color == preset ? 0.7 : 0), lineWidth: 2)
                                }
                                .onTapGesture { color = preset }
                                .accessibilityLabel("Preset color")
                        }
                        ColorPicker("", selection: $color, supportsOpacity: false)
                            .labelsHidden()
                    }
                }

                if colorIsTaken {
                    Label("Another account already uses this color.", systemImage: "exclamationmark.triangle.fill")
                        .font(.meta)
                        .foregroundStyle(.orange)
                }

                Section {
                    Toggle("Use the app’s normal account", isOn: $usesDefaultProfile)
                } footer: {
                    Text(usesDefaultProfile
                         ? "Opens the app signed in as it already is, but with this name and icon — so you can start it from here instead of its Dock icon. Nothing is kept separately, and removing this account never touches that data."
                         : "Turn this on for the account you were already signed into before Double Bubble. Everything then launches from one place, each with its own icon.")
                        .font(.meta)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 380)
        .onAppear {
            name = account.name
            color = account.color
            iconData = account.iconData
            usesDefaultProfile = account.usesDefaultProfile
        }
    }

    /// Mirrors the avatar on the card, so what you pick here is exactly what
    /// you'll see there — including the initial falling back live as you type.
    private var preview: some View {
        Group {
            if let iconData, let image = NSImage(data: iconData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(color.gradient)
                    .overlay {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func save() {
        var updated = account
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? account.name : trimmed
        updated.colorHex = NSColor(color).hexString
        updated.iconData = iconData
        updated.defaultProfile = usesDefaultProfile
        onSave(updated)
        dismiss()
    }
}
