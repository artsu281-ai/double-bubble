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
        let color = Color(hex: hex)

        return Button {
            colorHex = hex
        } label: {
            ZStack {
                // Flat. A swatch exists to show a colour exactly; a radial
                // gradient, a rim highlight and a coloured shadow all shift it,
                // so the dot you picked was never quite the dot you got.
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)

                if isSelected {
                    Circle()
                        .strokeBorder(palette.accentColor, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: Metrics.minHit, height: Metrics.minHit)
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
