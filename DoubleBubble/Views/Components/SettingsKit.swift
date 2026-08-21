import SwiftUI

// The shape of a settings screen: a serif title, then sections of cards, and
// inside each card rows that say what the control does before you touch it.
//
// The pattern is borrowed from Intact, the other app in this house, so the two
// read as siblings rather than as two people's guesses at the same palette.
// What makes it worth borrowing isn't the rounded corners — it's that every
// row carries a sentence. A settings screen where each line is two words and a
// switch is compact and tells you nothing; the explanation belongs next to the
// control, not in documentation nobody opens.

/// A whole settings screen: title, then scrolling sections.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .padding(.horizontal, 32)
                .padding(.top, 30)
                .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.windowBackground)
    }
}

/// A group of rows under an optional section label.
struct SettingsCard<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: Content

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(palette.hairline, lineWidth: 1)
                        )
                )
        }
    }
}

/// One row: what it is, what it does, and the control that changes it.
///
/// `isFirst` suppresses the divider rather than the card drawing one below
/// every row — a trailing hairline above the card's own bottom edge reads as a
/// misprint.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var isFirst: Bool = false
    @ViewBuilder var control: Control

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

/// A row whose content spans the full width — pickers made of cards, mostly,
/// where a control pinned to the right would have nowhere to go.
struct SettingsWideRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var isFirst: Bool = false
    @ViewBuilder var content: Content

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}
