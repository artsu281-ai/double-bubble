import SwiftUI

/// Sits above the window's content when a newer release exists.
///
/// Deliberately only a link: the app is signed ad hoc, so installing an update
/// always means the user approving the new copy themselves — a one-click
/// "Update" button here would be promising something it can't do.
struct UpdateBanner: View {
    let release: UpdateChecker.Release
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: Metrics.s) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(palette.accentColor)
                .accessibilityHidden(true)

            Text(L("Double Bubble \(release.version) is available."))
                .font(.listItem)

            Link(L("What’s new"), destination: release.url)
                .font(.listItem)
                .fontWeight(.medium)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.meta)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("Hide until the next release"))
            .accessibilityLabel(L("Hide until the next release"))
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accentColor.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSummaryElement)
    }
}
