import SwiftUI

// MARK: - Bulk plan
//
// The settings behind "make me five of these". Kept as a value type because it
// is three different things at once: the live state of the wizard, the thing
// saved as a preset, and the thing the executor reads — and all three going
// through one struct is what stops the saved preset drifting from what the
// wizard can express.

struct BulkPlan: Codable, Equatable {

    enum Numbering: String, Codable, CaseIterable, Identifiable {
        /// 1, 2, 3 — reads naturally up to nine.
        case plain
        /// 01, 02, 03 — sorts correctly in Finder and in the app's own list
        /// once there are ten or more, which is the whole reason it exists.
        case padded

        var id: String { rawValue }

        @MainActor
        var label: String { self == .plain ? L("1, 2, 3") : L("01, 02, 03") }
    }

    enum ColorMode: Codable, Equatable {
        /// Walk the house palette, skipping colours this app already uses.
        case auto
        /// One colour for the whole batch — useful when the batch itself is
        /// the group, and telling its members apart matters less than telling
        /// the group apart from everything else.
        case single(String)
    }

    /// Where the data comes from. The source account is not stored: a preset
    /// has to stay usable on an app that has never heard of it, so the source
    /// is chosen when the plan runs, not when it is saved.
    var copiesSource: Bool = false
    var groups: Set<DataGroup> = Set(DataGroup.ordered.filter(\.isOnByDefault))

    var count: Int = 3
    var nameTemplate: String = "Account {n}"
    var numbering: Numbering = .plain
    var colorMode: ColorMode = .auto

    /// The token the template substitutes. One token, on purpose: it covers
    /// every case anyone has actually wanted, and a second one would turn a
    /// text field into a syntax nobody can guess without documentation.
    static let token = "{n}"

    /// Sensible upper bound for the stepper. Not a hard limit — the warning on
    /// the review step is a better teacher than a disabled control — but past
    /// this an Electron app's copies run into tens of gigabytes.
    static let softMaximum = 50

    /// The names this plan would produce, in order.
    func names() -> [String] {
        let width = numbering == .padded ? max(2, String(count).count) : 1
        let template = nameTemplate.contains(Self.token)
            ? nameTemplate
            // No token means the number still has to land somewhere, and the
            // end is where anyone writing "qa" expects it. Saying so in the
            // preview beats a validation error explaining the syntax.
            : nameTemplate + " " + Self.token

        return (1...max(1, count)).map { index in
            let number = String(format: "%0\(width)d", index)
            return template.replacingOccurrences(of: Self.token, with: number)
        }
    }

    /// First few names plus a count, for the live preview line.
    func previewNames(limit: Int = 4) -> (shown: [String], remaining: Int) {
        let all = names()
        guard all.count > limit else { return (all, 0) }
        return (Array(all.prefix(limit)), all.count - limit)
    }

    /// Colours for the batch, avoiding what the app already uses when on auto.
    func colors(avoiding used: [String]) -> [String] {
        switch colorMode {
        case .single(let hex):
            return Array(repeating: hex, count: count)
        case .auto:
            let free = Account.presetColors.filter { !used.contains($0) }
            // Once the free colours run out, keep going round the full palette
            // rather than repeating one colour for everything left over.
            let pool = free.isEmpty ? Account.presetColors : free + Account.presetColors
            return (0..<count).map { pool[$0 % pool.count] }
        }
    }
}

// MARK: - Preset

/// A named `BulkPlan`, so a batch someone sets up once can be run again from a
/// menu without walking the wizard.
struct AccountPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var plan: BulkPlan

    /// Shown in the menu: "QA rig (5)".
    var menuTitle: String { "\(name) (\(plan.count))" }
}
