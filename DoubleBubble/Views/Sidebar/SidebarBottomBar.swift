import SwiftUI

/// The strip along the bottom of the source list: add, remove, view options.
///
/// Replaces a full-width "Add App…" button that sat *above* the search field.
/// The reasoning for putting it there was that adding an app is the first
/// thing anyone does — true, and the empty state now carries that job with a
/// prominent button and room to explain itself. What the top strip cost was
/// the convention: every macOS source list that can be added to has these
/// controls under it, and putting them somewhere else means they get looked
/// for in two places.
struct SidebarBottomBar: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue
    @AppStorage("showAccountDiskUsage") private var showDiskUsage = true

    private var selectedApp: ManagedApp? {
        ui.selectedAppID.flatMap { library.app($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 0) {
                Button {
                    ui.present(.addApp)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: Metrics.minHit, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L("Add an application"))
                .accessibilityLabel(L("Add an application"))

                Button {
                    guard let app = selectedApp else { return }
                    ui.confirmation = .removeApp(appID: app.id, name: app.name)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: Metrics.minHit, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(selectedApp == nil)
                .help(selectedApp.map { L("Remove \($0.name)") } ?? L("Select an application first"))
                .accessibilityLabel(L("Remove the selected application"))

                Spacer(minLength: 0)

                Menu {
                    Picker(L("Sort"), selection: $ui.sortOrder) {
                        ForEach(LibraryUIState.SortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Picker(L("Density"), selection: $densityRaw) {
                        ForEach(InterfaceDensity.allCases) { density in
                            Text(density.label).tag(density.rawValue)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Toggle(L("Show Disk Usage"), isOn: $showDiskUsage)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: Metrics.minHit, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("View options"))
                .accessibilityLabel(L("View options"))
            }
            .padding(.horizontal, Metrics.xs)
            .padding(.vertical, 3)
            .foregroundStyle(.secondary)
        }
        .background(.bar)
    }
}
