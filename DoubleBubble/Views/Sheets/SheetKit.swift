import SwiftUI

// The shape of every sheet in the app: a title that says what this is, an
// optional line that says what it does, the form, and a button bar pinned to
// the bottom. Written once so the four sheets can't drift into four different
// paddings and three different button orders.

struct SheetShell<Content: View, Buttons: View>: View {
    let title: String
    var subtitle: String?
    var width: CGFloat = Metrics.sheetWide
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(title)
                    .font(.system(.title3, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Metrics.xl)
            .padding(.top, Metrics.xl)
            .padding(.bottom, Metrics.l)
            .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    content
                }
                .padding(.horizontal, Metrics.xl)
                .padding(.bottom, Metrics.l)
            }
            .frame(maxHeight: Metrics.sheetMaxHeight)
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            HStack(spacing: Metrics.s) {
                buttons
            }
            .padding(Metrics.l)
        }
        .frame(width: width)
        .background(palette.windowBackground)
    }
}

/// A titled group of rows inside a sheet, matching the settings cards so the
/// two halves of the app look like one app.
struct SheetGroup<Content: View>: View {
    var header: String?
    @ViewBuilder var content: Content

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if let header {
                Text(header.uppercased())
                    .font(.sectionLabel)
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(Metrics.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                                .strokeBorder(palette.hairline, lineWidth: 1)
                        )
                )
        }
    }
}

/// A labelled row inside a sheet group, with the label column a fixed width so
/// several of them read as a form rather than as a stack of unrelated lines.
struct SheetRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 96
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            Text(label)
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Metrics.xs + 2)
    }
}

/// A checkbox with an explanation and a size on the right — the shape the
/// "what to carry over" list needs, and nothing else uses.
struct DataGroupToggle: View {
    let group: DataGroup
    let size: Int64
    @Binding var isOn: Bool
    var isFirst: Bool = false

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
                    .padding(.vertical, Metrics.s)
            }
            Toggle(isOn: $isOn) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.rowTitle)
                        Text(group.explanation)
                            .font(.meta)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Metrics.s)
                    Text(DiskUsage.string(for: size))
                        .font(.meta)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityValue(DiskUsage.string(for: size))
        }
    }
}

/// A progress line that always says which step it is on.
///
/// "A spinner and nothing else" is indistinguishable from a hang, which is
/// exactly what copying several hundred megabytes used to look like.
struct SheetProgress: View {
    let title: String
    var detail: String?
    var fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(title)
                .font(.rowTitle)

            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            if let detail {
                Text(detail)
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
