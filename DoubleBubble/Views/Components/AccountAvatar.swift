import SwiftUI

/// An account's face: its picture, or its initial on its colour.
///
/// One view for the row, the grid tile, the editor preview and the inspector,
/// so what you pick in the editor is exactly what turns up in the list. The
/// four used to be four separate `ZStack`s that had already drifted — the
/// editor drew a flat circle, the row drew a gradient.
struct AccountAvatar: View {
    let account: Account
    var size: CGFloat
    /// Draws a ring in the "running" colour. Deliberately not the account's
    /// own colour: identity and state are two systems, and one borrowing the
    /// other's channel is why the old card's border meant two things at once.
    var isRunning: Bool = false
    /// Live name, so the initial updates as it is typed in the editor rather
    /// than after saving.
    var nameOverride: String?
    /// Live picture, same reason.
    var iconOverride: Data??
    var colorOverride: Color?

    @Environment(\.themePalette) private var palette

    private var resolvedColor: Color { colorOverride ?? account.color }

    private var resolvedIcon: NSImage? {
        if let iconOverride {
            return iconOverride.flatMap(NSImage.init(data:))
        }
        return account.icon
    }

    private var initial: String {
        let source = nameOverride ?? account.name
        return String(source.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            if let image = resolvedIcon {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(resolvedColor.gradient)
                    .overlay {
                        Text(initial)
                            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if isRunning {
                Circle().strokeBorder(palette.success, lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The small dot that says an account is up.
///
/// Steady, never pulsing. It reports a state, not an alarm, and ten of them
/// breathing in a list turns a window into a string of fairy lights.
struct RunningDot: View {
    @Environment(\.themePalette) private var palette
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(palette.success)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// An icon-only button sized so it can actually be hit.
///
/// The row actions were 13pt glyphs with the system's default padding, which
/// put a real target of about 16pt next to a 44pt avatar. Everything here goes
/// through one wrapper so that can't happen again per-site.
struct RowActionButton: View {
    let symbol: String
    let help: String
    var glyphSize: CGFloat = 14
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize))
                .frame(width: Metrics.minHit, height: Metrics.minHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
