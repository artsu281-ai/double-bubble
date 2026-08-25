import SwiftUI
import AppKit

/// Pick how strongly an account colours its Dock tile — by looking at the
/// three tiles, not by reading three descriptions.
///
/// The whole problem this setting solves is visual ("I have three Claudes and
/// I can't find the right one"), so the control is the outcome itself: the
/// real artwork, really tinted, really badged. It follows the pattern the
/// Dock Icon settings page already uses, which is where anyone who has met
/// this idea before will have met it.
struct DockAccentPicker: View {
    @Binding var accent: IconAccent

    /// The app whose artwork is being tinted. `nil` while it can't be
    /// resolved, which hides the whole control rather than previewing a
    /// generic placeholder nobody will recognise.
    let appIcon: NSImage?
    let tint: Color
    let initial: String
    let bubbleCount: Int
    let accountImage: NSImage?

    @Environment(\.themePalette) private var palette
    @State private var tiles: [IconAccent: NSImage] = [:]

    var body: some View {
        HStack(spacing: Metrics.s) {
            ForEach(IconAccent.allCases) { option in
                tile(option)
            }
        }
        .task(id: renderKey) { await render() }
    }

    /// Everything the drawing depends on. Rebuilding three icons on every
    /// keystroke of the name field would be wasteful, and the name only
    /// reaches the tile when there is no mark to draw instead.
    private var renderKey: String {
        "\(NSColor(tint).hexString)|\(bubbleCount)|\(initial)|\(accountImage != nil)"
    }

    private func tile(_ option: IconAccent) -> some View {
        let isSelected = accent == option

        return Button {
            accent = option
        } label: {
            VStack(spacing: Metrics.xs) {
                Group {
                    if let image = tiles[option] {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.hairline)
                    }
                }
                .frame(width: 52, height: 52)

                Text(option.label)
                    .font(.meta)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.s)
            .padding(.horizontal, Metrics.xs)
            .background {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? palette.accentColor.opacity(0.12) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? palette.accentColor : palette.hairline,
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(option.explanation)
        .accessibilityLabel(option.label)
        .accessibilityHint(option.explanation)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Off the main thread: each tile is a full icon render, and three of them
    /// on every colour change would stutter the sheet.
    private func render() async {
        guard let appIcon else { return }
        let colour = NSColor(tint)
        let mark = accountImage
        let count = bubbleCount
        let letter = initial

        let rendered = await Task.detached(priority: .userInitiated) { () -> [IconAccent: NSImage] in
            var out: [IconAccent: NSImage] = [:]
            for option in IconAccent.allCases {
                if let image = IconFactory.preview(
                    base: appIcon, tint: colour, initial: letter,
                    accountImage: mark, bubbleCount: count, accent: option, points: 52
                ) {
                    out[option] = image
                }
            }
            return out
        }.value

        tiles = rendered
    }
}
