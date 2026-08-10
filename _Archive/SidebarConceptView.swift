import SwiftUI

// MARK: - Mock data
//
// A sketch of a multi-app data layer: one app, exactly two accounts,
// each account carrying its own identity color and run state.

struct MockAccount: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var colorHex: String
    var isRunning: Bool
    var unreadCount: Int = 0
    var uptime: String?

    var color: Color { Color(hex: colorHex) }
    var initial: String { String(name.prefix(1)).uppercased() }
}

struct MockApp: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var symbolName: String
    var isolationMethod: String
    var dataFolder: String
    var accounts: [MockAccount]   // always exactly 2

    var runningCount: Int { accounts.filter(\.isRunning).count }
    var unreadTotal: Int { accounts.reduce(0) { $0 + $1.unreadCount } }
}

enum MockData {
    static let apps: [MockApp] = [
        MockApp(name: "Telegram", symbolName: "paperplane.fill",
                isolationMethod: "Separate copy", dataFolder: "~/.double_bubble/bundle-A",
                accounts: [
                    MockAccount(name: "Personal", colorHex: "#0A84FF", isRunning: true, unreadCount: 12, uptime: "12 min"),
                    MockAccount(name: "Work", colorHex: "#30D158", isRunning: false, unreadCount: 3)
                ]),
        MockApp(name: "Slack", symbolName: "bubble.left.and.bubble.right.fill",
                isolationMethod: "Separate data folder", dataFolder: "~/.double_bubble/data/Slack-B",
                accounts: [
                    MockAccount(name: "Acme Corp", colorHex: "#FF9F0A", isRunning: false),
                    MockAccount(name: "Side Project", colorHex: "#BF5AF2", isRunning: true, unreadCount: 1, uptime: "3 min")
                ]),
        MockApp(name: "Discord", symbolName: "gamecontroller.fill",
                isolationMethod: "Separate data folder", dataFolder: "~/.double_bubble/data/Discord-A",
                accounts: [
                    MockAccount(name: "Friends", colorHex: "#64D2FF", isRunning: false),
                    MockAccount(name: "Modding", colorHex: "#FF375F", isRunning: false)
                ])
    ]
}

// MARK: - Root

struct SidebarConceptView: View {
    @State private var apps: [MockApp] = MockData.apps
    @State private var selection: MockApp.ID?

    private var selectedApp: MockApp? { apps.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 320)
        } detail: {
            if let app = selectedApp {
                AppDetailView(app: bind(app), onRemove: { remove(app.id) })
            } else {
                emptyDetail
            }
        }
        .onAppear { if selection == nil { selection = apps.first?.id } }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Apps") {
                ForEach(apps) { app in
                    HStack(spacing: 6) {
                        Label(app.name, systemImage: app.symbolName)
                            .font(.subheadline)
                            .lineLimit(1)

                        if app.runningCount > 0 {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .help("\(app.runningCount) of \(app.accounts.count) accounts running")
                                .accessibilityLabel("\(app.runningCount) of \(app.accounts.count) accounts running")
                        }

                        Spacer(minLength: 0)
                    }
                    .badge(app.unreadTotal)
                    .tag(app.id)
                    .contextMenu {
                        Button("Open Both") { setAll(running: true, for: app.id) }
                            .disabled(app.runningCount == app.accounts.count)
                        Button("Stop Both") { setAll(running: false, for: app.id) }
                            .disabled(app.runningCount == 0)
                        Divider()
                        Button("Show Data Folder in Finder") {}
                        Divider()
                        Button("Remove App", role: .destructive) { remove(app.id) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if apps.isEmpty { emptySidebar }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarAddButton(action: addApp)
        }
    }

    private var emptySidebar: some View {
        VStack(spacing: 4) {
            Text("No Apps Yet")
                .font(.subheadline.weight(.medium))
            Text("Add one below to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    private var emptyDetail: some View {
        ContentUnavailableView {
            Label(apps.isEmpty ? "No Apps Yet" : "No App Selected",
                  systemImage: "square.on.square.dashed")
        } description: {
            Text(apps.isEmpty
                 ? "Add an app to run it with two accounts side by side."
                 : "Choose an app in the sidebar, or add a new one.")
            .font(.subheadline)
        } actions: {
            Button("Add App…", action: addApp)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Actions

    private func addApp() {
        // A real build would open an NSOpenPanel here.
    }

    private func remove(_ id: MockApp.ID) {
        apps.removeAll { $0.id == id }
        if selection == id { selection = apps.first?.id }
    }

    private func setAll(running: Bool, for id: MockApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        for j in apps[i].accounts.indices {
            apps[i].accounts[j].isRunning = running
            apps[i].accounts[j].uptime = running ? "just now" : nil
        }
    }

    private func bind(_ app: MockApp) -> Binding<MockApp> {
        Binding(
            get: { apps.first(where: { $0.id == app.id }) ?? app },
            set: { new in
                if let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i] = new }
            }
        )
    }
}

// MARK: - Sidebar add button
//
// A full-width bottom bar, the way Reminders and Notes present their primary
// "new item" action: a divider to lift it off the list, a tinted glyph so it
// reads as an action rather than a disabled row, and a hover highlight that
// covers the whole strip so the hit target matches what the eye expects.

private struct SidebarAddButton: View {
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: action) {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                    Text("Add App…")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("Choose an app to run with two separate accounts")
            .onHover { isHovering = $0 }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

// MARK: - Detail

private struct AppDetailView: View {
    @Binding var app: MockApp
    var onRemove: () -> Void

    @State private var showAdvancedSettings = false

    var body: some View {
        Form {
            Section {
                ForEach($app.accounts) { $account in
                    AccountRow(account: $account)
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Both accounts run at the same time, each keeping its own login and data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("Advanced Settings", isExpanded: $showAdvancedSettings) {
                    LabeledContent("Isolation Method") {
                        Text(app.isolationMethod)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Data Folder") {
                        HStack(spacing: 6) {
                            Text(app.dataFolder)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button {} label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Show in Finder")
                        }
                    }
                }
                .font(.subheadline)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.name)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                ControlGroup {
                    Button {
                        setAll(running: true)
                    } label: {
                        Label("Open Both", systemImage: "play.fill")
                    }
                    .help("Open both accounts")
                    .disabled(app.runningCount == app.accounts.count)

                    Button {
                        setAll(running: false)
                    } label: {
                        Label("Stop Both", systemImage: "stop.fill")
                    }
                    .help("Stop both accounts")
                    .disabled(app.runningCount == 0)
                }
                .padding(.horizontal, 4)
            }
            ToolbarItem {
                Menu {
                    Button("Edit Accounts…") {}
                    Button("Show Data Folder in Finder") {}
                    Divider()
                    Button("Remove App", role: .destructive, action: onRemove)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("More actions for \(app.name)")
            }
        }
    }

    private var subtitle: String {
        switch app.runningCount {
        case 0: "No accounts running"
        case 1: "1 of 2 accounts running"
        default: "Both accounts running"
        }
    }

    private func setAll(running: Bool) {
        for i in app.accounts.indices {
            app.accounts[i].isRunning = running
            app.accounts[i].uptime = running ? "just now" : nil
        }
    }
}

// MARK: - Account row

private struct AccountRow: View {
    @Binding var account: MockAccount

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(account.color.gradient)
                .frame(width: 26, height: 26)
                .overlay {
                    Text(account.initial)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.subheadline)
                status
            }

            Spacer(minLength: 8)

            if account.unreadCount > 0 {
                unreadBadge
            }

            if account.isRunning {
                Button {} label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Bring \(account.name) to the front")
            }

            // Fixed width so the row doesn't reflow as the label flips Open/Stop.
            Button(account.isRunning ? "Stop" : "Open") {
                toggle()
            }
            .frame(width: 62)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(account.isRunning ? "Stop" : "Open") { toggle() }
            Button("Bring to Front") {}
                .disabled(!account.isRunning)
            Divider()
            Button("Rename…") {}
        }
    }

    private var unreadBadge: some View {
        Text("\(account.unreadCount)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red, in: Capsule())
            .help("\(account.unreadCount) unread")
            .accessibilityLabel("\(account.unreadCount) unread messages")
    }

    @ViewBuilder
    private var status: some View {
        if account.isRunning {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                Text("Running")
                if let uptime = account.uptime {
                    Text("· \(uptime)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text("Not running")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggle() {
        account.isRunning.toggle()
        account.uptime = account.isRunning ? "just now" : nil
    }
}

#Preview {
    SidebarConceptView()
        .frame(width: 880, height: 560)
}
