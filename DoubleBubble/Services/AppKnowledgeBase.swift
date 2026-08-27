import Foundation

// MARK: - App Knowledge Base
//
// Describes how to isolate each known application's data directory.
// Built from research across public documentation, Electron framework docs,
// and community knowledge — no code copied from any project.
//
// Each entry maps a bundle ID prefix to an IsolationDescriptor.

struct IsolationDescriptor {
    /// Strategy for isolation
    enum Kind {
        /// Electron/Chromium: pass --user-data-dir=<path>
        case electronUserDataDir
        /// JetBrains: pass -Didea.config.path and -Didea.system.path via vmOptions
        case jetbrainsVMOptions
        /// Apps that accept a generic --profile-directory or --config-dir flag.
        ///
        /// `separateValue` picks the argument shape: `false` yields
        /// `--config-dir=/path` (GNU style), `true` yields `-workdir /path`
        /// (two argv entries), which is what Qt-based apps like Telegram
        /// Desktop expect.
        case configDir(flag: String, separateValue: Bool)
        /// Native apps: copy bundle + patch Bundle ID
        case bundleCopy

        /// Copy the bundle *and* pass a data-directory flag to the copy.
        ///
        /// Needed for sandboxed apps that accept a working-directory flag but
        /// can't use it while sandboxed: the copy is re-signed ad-hoc, which
        /// drops the sandbox entitlement, and only then may it write to a path
        /// we choose. Copying alone isn't enough — without the flag both copies
        /// fall back to the same shared support directory and the second one
        /// exits on the first one's single-instance lock.
        case copyThenFlag(flag: String, separateValue: Bool)
    }

    let kind: Kind
    /// Human-readable description shown in the UI
    let description: String
    /// Whether data is preserved between sessions (user data dir approach)
    let persistsData: Bool

    /// This app has to run from the bundle it was installed in — never a copy.
    ///
    /// Chromium browsers are the case that matters. They ship with library
    /// validation, and their launcher re-executes through the app bundle,
    /// which drops the argv we passed. A copy therefore ignores
    /// `--user-data-dir` and quietly falls back to the *default* profile —
    /// the same one the real browser uses — so the two fight over one
    /// singleton lock and whichever starts second simply can't open.
    ///
    /// This is the constraint the per-account Dock icon has to yield to: no
    /// copy means no place to put a branded icon, and a working second
    /// profile is worth more than a prettier tile.
    var requiresOriginalBundle: Bool = false
}

// MARK: - Known App Registry

enum AppKnowledgeBase {

    // Ordered from most-specific to least-specific bundle ID prefix
    static let registry: [(prefix: String, descriptor: IsolationDescriptor)] = [

        // ── AI / IDE ────────────────────────────────────────────────
        //
        // Claude Desktop signs its own Keychain items into access groups
        // scoped by Anthropic's Team ID (`keychain-access-groups`, verified
        // via `codesign -d --entitlements`), not by --user-data-dir. Two
        // copies launched from the *same* signed bundle share that Team ID,
        // so they share those Keychain items too — signing into one account
        // there can rotate a credential the other account's session depends
        // on and silently sign it out. A plain --user-data-dir isolates the
        // Chromium profile but never touches this. Copying the bundle and
        // re-signing it ad-hoc drops the entitlement entirely, so the copy
        // can't reach that Keychain group at all — genuinely separate, not
        // just cosmetically separate.
        ("com.anthropic.claudefordesktop",
         IsolationDescriptor(kind: .copyThenFlag(flag: "--user-data-dir", separateValue: false),
                             description: "Claude Desktop (isolated copy)",
                             persistsData: true)),

        ("com.openai.chat",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "ChatGPT Desktop (Electron)",
                             persistsData: true)),

        ("com.todesktop.230313mzl4w4u92",  // Cursor
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Cursor (Electron/VSCode fork)",
                             persistsData: true)),

        // Two separate Google products, not one app that renamed itself —
        // `Antigravity` and `Antigravity IDE` install side by side, each with
        // its own bundle id and its own default user data directory
        // (`~/Library/Application Support/Antigravity` and `…/Antigravity
        // IDE`). Both are VS Code forks and both take `--user-data-dir`, so
        // both are listed: recognised by identifier rather than by sniffing
        // for the Electron framework, which says an app *is* Electron but
        // nothing about how to isolate it.
        ("com.google.antigravity-ide",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Antigravity IDE (Electron/VSCode fork)",
                             persistsData: true)),

        ("com.google.antigravity",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Antigravity (Electron/VSCode fork)",
                             persistsData: true)),

        ("com.exafunction.windsurf",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Windsurf (Electron)",
                             persistsData: true)),

        ("com.microsoft.VSCode",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Visual Studio Code (Electron)",
                             persistsData: true)),

        ("com.microsoft.vscode",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "VS Code (Electron)",
                             persistsData: true)),

        ("dev.zed.zed",
         IsolationDescriptor(kind: .configDir(flag: "--config-dir", separateValue: false),
                             description: "Zed Editor",
                             persistsData: true)),

        // ── JetBrains ───────────────────────────────────────────────
        // JetBrains IDEs accept -Didea.config.path via environment IDEA_PROPERTIES
        ("com.jetbrains.intellij",
         IsolationDescriptor(kind: .jetbrainsVMOptions,
                             description: "IntelliJ IDEA",
                             persistsData: true)),

        ("com.jetbrains.pycharm",
         IsolationDescriptor(kind: .jetbrainsVMOptions,
                             description: "PyCharm",
                             persistsData: true)),

        ("com.jetbrains.webstorm",
         IsolationDescriptor(kind: .jetbrainsVMOptions,
                             description: "WebStorm",
                             persistsData: true)),

        ("com.jetbrains.goland",
         IsolationDescriptor(kind: .jetbrainsVMOptions,
                             description: "GoLand",
                             persistsData: true)),

        ("com.jetbrains.rustrover",
         IsolationDescriptor(kind: .jetbrainsVMOptions,
                             description: "RustRover",
                             persistsData: true)),

        ("com.jetbrains.rider",
         IsolationDescriptor(kind: .jetbrainsVMOptions,
                             description: "Rider",
                             persistsData: true)),

        ("com.jetbrains.clion",
         IsolationDescriptor(kind: .jetbrainsVMOptions,
                             description: "CLion",
                             persistsData: true)),

        // ── Communication ───────────────────────────────────────────
        ("com.tinyspeck.slackmacgap",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Slack (Electron)",
                             persistsData: true)),

        ("com.discord",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Discord (Electron)",
                             persistsData: true)),

        ("com.hnc.Discord",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Discord (Electron)",
                             persistsData: true)),

        // Telegram for macOS (the Swift client). Sandboxed *and* built around
        // two App Groups, so a re-signed copy is locked out of its own data.
        // The sandbox check in LaunchEngine rejects it; there is no workaround
        // that doesn't require Telegram's own signing identity.
        ("ru.keepcoder.Telegram",
         IsolationDescriptor(kind: .bundleCopy,
                             description: "Telegram for macOS (native, App Group)",
                             persistsData: false)),

        // Telegram Desktop from the App Store. Sandboxed but uses no App
        // Group, so re-signing a copy is safe — and the copy, no longer
        // sandboxed, accepts `-workdir` for a per-account data directory.
        ("org.telegram.desktop",
         IsolationDescriptor(kind: .copyThenFlag(flag: "-workdir", separateValue: true),
                             description: "Telegram Desktop (App Store)",
                             persistsData: true)),

        // Telegram Desktop from telegram.org is not sandboxed and takes
        // `-workdir <path>`, so it needs no copying at all.
        ("com.tdesktop.Telegram",
         IsolationDescriptor(kind: .configDir(flag: "-workdir", separateValue: true),
                             description: "Telegram Desktop (direct)",
                             persistsData: true)),

        // ── Browsers ────────────────────────────────────────────────
        // Chromium browsers have taken --user-data-dir since forever, and they
        // must use it: they ship with library validation, so a re-signed copy
        // is refused by macOS outright ("Can't open the application").
        ("com.google.Chrome",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Google Chrome",
                             persistsData: true,
                             requiresOriginalBundle: true)),

        ("com.microsoft.edgemac",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Microsoft Edge",
                             persistsData: true,
                             requiresOriginalBundle: true)),

        ("com.brave.Browser",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Brave",
                             persistsData: true,
                             requiresOriginalBundle: true)),

        ("com.vivaldi.Vivaldi",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Vivaldi",
                             persistsData: true,
                             requiresOriginalBundle: true)),

        ("com.operasoftware.Opera",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Opera",
                             persistsData: true,
                             requiresOriginalBundle: true)),

        ("ru.yandex.desktop.yandex-browser",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Yandex Browser",
                             persistsData: true,
                             requiresOriginalBundle: true)),

        ("company.thebrowser.Browser",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Arc",
                             persistsData: true)),

        // ── Design / Productivity ───────────────────────────────────
        ("com.figma.desktop",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Figma (Electron)",
                             persistsData: true)),

        ("com.linear",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Linear (Electron)",
                             persistsData: true)),

        ("notion.id",
         IsolationDescriptor(kind: .electronUserDataDir,
                             description: "Notion (Electron)",
                             persistsData: true)),

        // ── Music / Media ───────────────────────────────────────────
        ("com.spotify.client",
         IsolationDescriptor(kind: .bundleCopy,
                             description: "Spotify (Native)",
                             persistsData: false)),
    ]

    // MARK: - Lookup

    /// Apps that already ship their own account switcher. When Double Bubble
    /// can't isolate one of them, pointing at the built-in feature helps more
    /// than explaining the code-signing problem.
    static func builtInMultiAccountHint(forBundleID bundleID: String) -> String? {
        let known: [(prefix: String, hint: String)] = [
            ("ru.keepcoder.Telegram",
             "Telegram for macOS holds several accounts on its own: Settings → click your name → Add Account."),
            ("com.tinyspeck.slackmacgap",
             "Slack signs into several workspaces on its own — use the workspace switcher in its sidebar."),
        ]
        for (prefix, hint) in known where bundleID.lowercased().hasPrefix(prefix.lowercased()) {
            return hint
        }
        return nil
    }

    /// A different build of the same product that Double Bubble *can* isolate.
    ///
    /// Telegram is the motivating case: the native client is locked down by its
    /// App Group, while Telegram Desktop keeps everything in a plain folder.
    /// Naming the working build turns a dead end into one click.
    struct Alternative {
        /// Bundle ids to look for on disk, most preferred first.
        let bundleIDs: [String]
        /// What to call it when none of them is installed.
        let name: String
        /// Why this one works, and where to get it.
        let note: String
    }

    static func alternative(forBundleID bundleID: String) -> Alternative? {
        let known: [(prefix: String, alternative: Alternative)] = [
            ("ru.keepcoder.Telegram",
             Alternative(
                bundleIDs: ["org.telegram.desktop", "com.tdesktop.Telegram"],
                name: "Telegram Desktop",
                note: "Telegram Desktop — called Telegram Lite in the App Store — "
                    + "keeps its data in an ordinary folder instead of an App Group, "
                    + "so it can run twice. Install it and add that one instead."
             )),
        ]
        for (prefix, alternative) in known
        where bundleID.lowercased().hasPrefix(prefix.lowercased()) {
            return alternative
        }
        return nil
    }

    static func descriptor(forBundleID bundleID: String) -> IsolationDescriptor? {
        for (prefix, descriptor) in registry {
            if bundleID.lowercased().hasPrefix(prefix.lowercased()) {
                return descriptor
            }
        }
        return nil
    }

    /// Returns a descriptor for any Electron app (detected by framework)
    static func electronFallback() -> IsolationDescriptor {
        IsolationDescriptor(
            kind: .electronUserDataDir,
            description: "Electron app (auto-detected)",
            persistsData: true
        )
    }

    static func nativeFallback() -> IsolationDescriptor {
        IsolationDescriptor(
            kind: .bundleCopy,
            description: "Native app",
            persistsData: false
        )
    }
}
