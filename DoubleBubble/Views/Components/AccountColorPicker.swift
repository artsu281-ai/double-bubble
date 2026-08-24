import SwiftUI
import AppKit

/// The six house colours, plus a way out to any other one.
///
/// Was six `Circle`s with `.onTapGesture`, which looks identical and is not
/// the same thing at all: a tap gesture has no focus ring, no keyboard
/// activation, and no accessibility role — VoiceOver saw six unlabelled
/// images. Real `Button`s cost nothing and behave.
struct AccountColorPicker: View {
    @Binding var colorHex: String
    /// Colours the siblings already use, flagged rather than forbidden.
    var usedColors: Set<String> = []

    @Environment(\.themePalette) private var palette

    private var isCustom: Bool { !Account.presetColors.contains(colorHex) }

    private var customBinding: Binding<Color> {
        Binding(
            get: { Color(hex: colorHex) },
            set: { colorHex = NSColor($0).hexString }
        )
    }

    var body: some View {
        HStack(spacing: Metrics.s) {
            ForEach(Account.presetColors, id: \.self) { hex in
                swatch(hex)
            }

            ColorPicker(L("Custom colour"), selection: customBinding, supportsOpacity: false)
                .labelsHidden()
                .help(L("Pick any other colour"))
                .overlay {
                    if isCustom {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.primary.opacity(0.7), lineWidth: 2)
                            .padding(-3)
                    }
                }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = colorHex == hex
        let isTaken = usedColors.contains(hex)

        return Button {
            colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 20, height: 20)
                // A first pass drew a ring inside taken swatches to mark
                // them. On screen that is indistinguishable from a radio
                // button, so a row of six colours read as a second, nested
                // set of choices. The collision is called out in words under
                // the picker instead — which is where it matters, since only
                // the colour actually chosen can collide — and the tooltip
                // still names it on hover.
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(isSelected ? 0.7 : 0), lineWidth: 2)
                        .padding(-3)
                }
                .frame(width: Metrics.minHit - 4, height: Metrics.minHit - 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName(for: hex))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(isTaken ? L("Already used by another account") : accessibilityName(for: hex))
    }

    /// Colours have to be nameable for anyone who can't see them, and "colour
    /// number four" is not a name.
    private func accessibilityName(for hex: String) -> String {
        switch hex {
        case Account.presetColors[0]: return L("Denim")
        case Account.presetColors[1]: return L("Teal")
        case Account.presetColors[2]: return L("Moss")
        case Account.presetColors[3]: return L("Amber")
        case Account.presetColors[4]: return L("Plum")
        case Account.presetColors[5]: return L("Rose")
        default: return L("Custom colour")
        }
    }
}
