import SwiftUI

/// The strip along the bottom of the source list: add, remove, view options.
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

            HStack(spacing: 4) {
                Button {
                    ui.present(.addApp)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: Metrics.minHit, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .help(L("Add an application"))
                .accessibilityLabel(L("Add an application"))

                Button {
                    guard let app = selectedApp else { return }
                    ui.confirmation = .removeApp(appID: app.id, name: app.name)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: Metrics.minHit, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(selectedApp == nil)
                .foregroundStyle(selectedApp != nil ? Color.primary : Color.secondary.opacity(0.5))
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
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: Metrics.minHit, height: 26)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.primary)
                .help(L("View options"))
                .accessibilityLabel(L("View options"))
            }
            .padding(.horizontal, Metrics.m)
            .padding(.vertical, 4)
        }
        .background(.bar)
    }
}
