import Foundation
import Combine

final class ProfileStore: ObservableObject {

    // MARK: - Slots
    @Published var profileA: Profile {
        didSet { save() }
    }
    @Published var profileB: Profile {
        didSet { save() }
    }

    // MARK: - Running instances (in-memory only)
    @Published var instanceA: AppInstance?
    @Published var instanceB: AppInstance?

    // MARK: - Persistence key
    private let udKey = "com.doublebubble.profiles"

    init() {
        if let data = UserDefaults.standard.data(forKey: "com.doublebubble.profiles"),
           let decoded = try? JSONDecoder().decode([String: Profile].self, from: data) {
            profileA = decoded["A"] ?? .defaultA
            profileB = decoded["B"] ?? .defaultB
        } else {
            profileA = .defaultA
            profileB = .defaultB
        }
    }

    // MARK: - Save
    func save() {
        let dict: [String: Profile] = ["A": profileA, "B": profileB]
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    // MARK: - Helpers
    func profile(for slot: Slot) -> Profile {
        slot == .a ? profileA : profileB
    }

    func setProfile(_ profile: Profile, for slot: Slot) {
        if slot == .a { profileA = profile } else { profileB = profile }
    }

    func instance(for slot: Slot) -> AppInstance? {
        slot == .a ? instanceA : instanceB
    }

    func setInstance(_ instance: AppInstance?, for slot: Slot) {
        if slot == .a { instanceA = instance } else { instanceB = instance }
    }
}

enum Slot: String, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"
    public var id: String { rawValue }
}
