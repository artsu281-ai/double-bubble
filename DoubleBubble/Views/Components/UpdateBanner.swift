import SwiftUI

/// Sits above the window's content when a newer release exists.
///
/// It used to be a link and nothing more, on the reasoning that an ad-hoc
/// signature meant an "Update" button would be promising something it couldn't
/// deliver. That reasoning was wrong on the facts — see `Updater` — so the
/// button is here, and the link stays beside it for anyone who would rather
/// read what changed before taking it.
struct UpdateBanner: View {
    let release: UpdateChecker.Release
    let onDismiss: () -> Void

    @ObservedObject private var updater = Updater.shared
    @Environment(\.themePalette) private var palette

    private var canInstall: Bool {
        release.downloadURL != nil && Updater.canReplaceItself
    }

    var body: some View {
        HStack(spacing: Metrics.s) {
            Image(systemName: symbol)
                .foregroundStyle(isFailed ? palette.warning : palette.accentTextColor)
                .accessibilityHidden(true)

            Text(message)
                .font(.listItem)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !updater.isBusy {
                Link(L("What’s new"), destination: release.url)
                    .font(.listItem)
                    .fontWeight(.medium)
            }

            Spacer(minLength: Metrics.s)

            if updater.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, Metrics.xs)
            } else if canInstall {
                Button(isFailed ? L("Try Again") : L("Update and Restart")) {
                    updater.install(release)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.meta)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(updater.isBusy)
            .help(L("Hide until the next release"))
            .accessibilityLabel(L("Hide until the next release"))
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isFailed ? palette.warning : palette.accentColor).opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSummaryElement)
    }

    private var isFailed: Bool {
        if case .failed = updater.phase { return true }
        return false
    }

    private var symbol: String {
        isFailed ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill"
    }

    /// One line that says where things stand, rather than a banner that keeps
    /// saying "available" while it is halfway through installing.
    private var message: String {
        switch updater.phase {
        case .downloading:
            return L("Downloading Double Bubble \(release.version)…")
        case .verifying:
            return L("Checking the download…")
        case .installing:
            return L("Installing. Double Bubble will reopen by itself.")
        case .failed(let reason):
            return reason
        case .idle:
            if canInstall {
                return L("Double Bubble \(release.version) is available.")
            }
            // No archive, or this copy sits somewhere it may not overwrite —
            // an app installed for every user, or a build running out of
            // Xcode. Saying so beats a button that can only fail.
            return L("Double Bubble \(release.version) is available — download it from the release page.")
        }
    }
}
