import SwiftUI

/// Everything the main window remembers about how it is being looked at.
///
/// This used to be seven `@State` properties scattered across `LibraryView`
/// and its private subviews, which was fine while nothing outside the view
/// hierarchy needed to reach them. Two things now do: the main menu, whose
/// commands live outside any window and have to be able to say "duplicate the
/// selected account", and the toolbar, which has to open sheets owned by a
/// view three levels down.
///
/// One shared object is correct here specifically because there is exactly one
/// main window — a `Window`, not a `WindowGroup`. With several windows this
/// would have to be a `@FocusedObject`, and the extra ceremony would be
/// earning nothing.
@MainActor
final class LibraryUIState: ObservableObject {

    // MARK: Navigation

    enum SidebarItem: Hashable {
        /// Everything at once: what is running, what it costs, what needs attention.
        case overview
        /// A flat list across every app, with filters.
        case allAccounts
        case app(UUID)
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list, grid
        var id: String { rawValue }

        @MainActor
        var label: String { self == .list ? L("List") : L("Grid") }
        var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        /// The order apps were added, pinned ones first. The default, because
        /// it is the only one that never moves under the user.
        case added
        case name
        case lastOpened

        var id: String { rawValue }

        @MainActor
        var label: String {
            switch self {
            case .added:      return L("By When Added")
            case .name:       return L("By Name")
            case .lastOpened: return L("By Last Opened")
            }
        }
    }

    /// Which slice of "All Accounts" is showing.
    enum AccountFilter: String, CaseIterable, Identifiable {
        case all, running, neverOpened, large

        var id: String { rawValue }

        @MainActor
        var label: String {
            switch self {
            case .all:         return L("All")
            // Not the row's "Running": in Russian that is an adjective
            // agreeing with a single account and cannot name a filter.
            case .running:     return L("Running only")
            case .neverOpened: return L("Never Opened")
            case .large:       return L("Over 1 GB")
            }
        }
    }

    // MARK: Sheets

    enum Route: Identifiable {
        case addApp
        case newAccount(appID: UUID)
        case editAccount(appID: UUID, account: Account)
        case duplicate(appID: UUID, account: Account)
        case bulkCreate(appID: UUID, preset: AccountPreset?)

        var id: String {
            switch self {
            case .addApp:                       return "addApp"
            case .newAccount(let appID):        return "new-\(appID)"
            case .editAccount(_, let account):  return "edit-\(account.id)"
            case .duplicate(_, let account):    return "dup-\(account.id)"
            case .bulkCreate(let appID, _):     return "bulk-\(appID)"
            }
        }
    }

    /// Destructive confirmations, kept apart from `Route` because they are
    /// alerts rather than sheets and the two must never fight over the screen.
    enum Confirmation: Identifiable {
        case removeApp(appID: UUID, name: String)
        case removeAccounts(appID: UUID, ids: Set<UUID>, names: [String])
        case clearData(appID: UUID, account: Account)

        var id: String {
            switch self {
            case .removeApp(let appID, _):      return "rmApp-\(appID)"
            case .removeAccounts(_, let ids, _): return "rmAcc-\(ids.count)-\(ids.first?.uuidString ?? "")"
            case .clearData(_, let account):    return "clear-\(account.id)"
            }
        }
    }

    // MARK: State

    @Published var sidebarSelection: SidebarItem? = .overview
    /// Multiple selection: the batch actions over existing accounts are just
    /// this plus a toolbar, which is far less machinery than a second "bulk
    /// operations" screen would have been.
    @Published var accountSelection: Set<UUID> = []
    @Published var appSearch = ""
    @Published var accountFilter: AccountFilter = .all

    @Published var route: Route?
    @Published var confirmation: Confirmation?
    @Published var errorMessage: String?

    /// Accounts that just appeared, so the list can point at them for a
    /// moment. Without it a batch of five lands silently in a list of twelve.
    @Published private(set) var highlighted: Set<UUID> = []

    @Published var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Keys.viewMode) }
    }
    @Published var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }
    @Published var showInspector: Bool {
        didSet { UserDefaults.standard.set(showInspector, forKey: Keys.inspector) }
    }

    private enum Keys {
        static let viewMode = "libraryViewMode"
        static let sortOrder = "librarySortOrder"
        static let inspector = "libraryShowInspector"
    }

    init() {
        let defaults = UserDefaults.standard
        viewMode = ViewMode(rawValue: defaults.string(forKey: Keys.viewMode) ?? "") ?? .list
        sortOrder = SortOrder(rawValue: defaults.string(forKey: Keys.sortOrder) ?? "") ?? .added
        showInspector = defaults.object(forKey: Keys.inspector) as? Bool ?? false
    }

    // MARK: Derived

    /// The app currently on screen, if the sidebar is pointing at one.
    var selectedAppID: UUID? {
        if case .app(let id) = sidebarSelection { return id }
        return nil
    }

    /// The single selected account, when exactly one is selected. Most of the
    /// menu commands only make sense for one.
    var singleAccountID: UUID? {
        accountSelection.count == 1 ? accountSelection.first : nil
    }

    var hasMultipleSelected: Bool { accountSelection.count > 1 }

    // MARK: Commands

    func select(app id: UUID) {
        sidebarSelection = .app(id)
        accountSelection = []
    }

    func selectOnly(account id: UUID) {
        accountSelection = [id]
    }

    func toggle(account id: UUID) {
        if accountSelection.contains(id) { accountSelection.remove(id) }
        else { accountSelection.insert(id) }
    }

    /// Marks freshly created accounts and clears the mark on its own.
    ///
    /// A highlight that has to be dismissed is a notification; this is meant
    /// to be a glance, so it expires whether or not anyone was looking.
    func highlight(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        highlighted.formUnion(ids)
        accountSelection = Set(ids)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self else { return }
            self.highlighted.subtract(ids)
        }
    }

    func present(_ route: Route) {
        // A sheet on top of a sheet is a macOS bug report waiting to happen;
        // an alert already up means the user is being asked something.
        guard confirmation == nil else { return }
        self.route = route
    }
}
