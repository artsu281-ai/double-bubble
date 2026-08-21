# Interface

## Screens

### The main window — `LibraryView`

[`LibraryView.swift`](../DoubleBubble/Views/LibraryView.swift) (1,200+
lines) is the app's one window, a `NavigationSplitView`:

- **Sidebar** — the list of `ManagedApp`s, with search (`.searchable`)
  and pinned (`isPinned`) apps always on top; the rest keep a stable order
  matching the order they were added in (a stable sort by
  `(pinned?, original index)`).
- **Detail** (`AppDetailView`) — cards for the selected app's accounts:
  status (running/stopped), an Open/Stop button, version (with a warning
  if a running copy has fallen behind the version on disk —
  `outdatedVersion`), a launch blocker with an explanation
  (`library.blocker(for:)`), and a button for a suggested alternative
  (`onUseAlternative`, see [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md)).
- **`AccountCard`** — a single account's card: an avatar (an initial on a
  colored background, or a custom picture), a name, a status. Its context
  menu, for accounts with their own signed copy
  (`AppLibrary.bundleCopyFolder(for:account:)` not `nil`), has a **Grant
  System Permissions** item — quick access to the copy in Finder, plus
  direct links to the Screen Recording/Accessibility panes in System
  Settings (`SystemSettingsPane`, see
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md)).
- **`AddAccountCard`** — a placeholder card for adding a new account to an
  app.
- **`SidebarAddButton`** — the entry point for adding a new app to the
  library (picking a `.app` via `NSOpenPanel`, behind
  `AppLibrary.addApp(at:)`).
- **`SettingsToolbarButton`** — the settings popover in the toolbar's
  top-right corner (see below for why it isn't a separate `⌘,` window).

Editing an account (`EditingAccount`, routed through `.sheet(item:)`) and
removing an app (`removingApp`, through `.alert`) are both driven by this
screen's local `@State`.

### `AccountEditorView`

[`AccountEditorView.swift`](../DoubleBubble/Views/AccountEditorView.swift)
is the modal form for editing a single account: name, a color from
`Account.presetColors` (excluding colors already used by other accounts
of the same app), and a custom picture via
[`AccountIcon.pickFromDisk()`](../DoubleBubble/Services/AccountIcon.swift).

### Settings — `SettingsView`

[`AboutSettingsView.swift`](../DoubleBubble/Views/AboutSettingsView.swift)
is **not a separate window** — it's a popover embedded in the main
window's toolbar. The reason is spelled out in the code: a SwiftUI
`Settings {}` scene would claim `⌘,` and create a second window with
partly the same functionality, duplicating controls in two places instead
of one. Four sections inside one scrolling `Form`, the same principle
macOS's own System Settings uses — what's rarely touched is kept separate
from what's used every day:

1. **Interface** (`InterfaceSettingsTab`) — the appearance theme
   ([`AppTheme`](#appearance-themes)) and interface density
   ([`InterfaceDensity`](#interface-density-interfacedensity)).
2. **General** (`GeneralSettingsTab`) — everyday toggles: launch at login
   ([`LaunchAtLogin`](../DoubleBubble/Services/LaunchAtLogin.swift)),
   notifications on launch failure.
3. **Language** (`LanguageSettingsSection`) — switching between EN/RU/
   System, see [below](#localization).
4. **Advanced** (`AdvancedSettingsTab`) — "dangerous" operations that need
   direct access to `library` (resetting/clearing data at the whole-
   library level).
5. **About** (`AboutSection`) — version, copyright, publisher logo
   (`PublisherLogo` from `Assets.xcassets`).

### Menu Bar Extra

Defined right in
[`DoubleBubbleApp.swift`](../DoubleBubble/DoubleBubbleApp.swift)
(`MenuBarMenuView`) — a list of apps and their accounts with status and an
Open/Stop button, reachable without opening the main window; the "Open
Double Bubble…" item recreates a closed main window via
`openWindow(id: "main")` (the plain `NSApp.windows` walk used before this
couldn't find a window that had already been closed — it just wasn't in
the list anymore).

### `BubbleMark`

[`Components/BubbleMark.swift`](../DoubleBubble/Views/Components/BubbleMark.swift)
is the animated mark: two "metaballs" drawn through a `Canvas` with an
`.alphaThreshold` + `.blur` filter, which is what makes them merge into a
single mass with a smooth "neck" between them as they come together, and
what makes that neck thin out and snap on its own as they part. Used
sparingly — in empty states and onboarding — rather than as a replacement
for system SF Symbols: ordinary functional icons (trash, folder, plus)
stay standard symbols everywhere, which is what people already recognize
them for.

Respects `accessibilityReduceMotion` (holds on the "fully split" frame if
the user has "Reduce Motion" turned on in System Settings).

## Appearance themes

[`AppTheme.swift`](../DoubleBubble/Services/AppTheme.swift) — 4 options:

- **Terracotta** ("Default" in the UI) — the house theme: a warm cream/
  clay palette, deliberately chosen to contrast with the cool blue-violet
  of Double Bubble's own logo, so the brand and the product read as
  distinct but related things. It has its own dark variant
  (`terracottaDark`) — not an inversion to gray, but a darker step of the
  same clay hue: plain gray next to a clay accent would read as two
  unrelated palettes.
- **System / Light / Dark** — use the system's own `NSColor`s
  (`.windowBackgroundColor`, `.controlBackgroundColor`) and don't override
  the accent color — they respect whatever the user picked globally in
  System Settings.

How it's applied (`ThemedModifier` / `.themed()`): the palette is threaded
through `Environment(\.themePalette)` rather than painted as one
`.background(...)` behind the window — `NavigationSplitView`, the sidebar,
and the cards all paint their own opaque system colors on top of each
other, so a plain window background would be completely covered up by
them. `preferredColorScheme` and the palette are always derived from the
same computed `effective` value, so surfaces and text never "disagree"
with each other (dark text on a dark background was a real bug, fixed
this way).

`success`/`danger` are also their own per theme, rather than the stock
`Color.red`/`.green` — those are tuned for pure white/black and looked
like neon stickers dropped on the theme's warm cream background.

## Interface density (`InterfaceDensity`)

[`InterfaceDensity.swift`](../DoubleBubble/Services/InterfaceDensity.swift)
is the single place sizes are computed from (avatar, name font, card
padding, sidebar icon size): `.comfortable` (the default — bigger, with
more room to breathe) and `.compact` (tighter, for people managing a lot
of apps who'd rather see more at once without scrolling).

## Localization

[`AppLanguage.swift`](../DoubleBubble/Services/AppLanguage.swift) — EN/RU
+ System; strings live in
[`Localizable.xcstrings`](../DoubleBubble/Localizable.xcstrings) (a String
Catalog, Xcode's modern format). macOS resolves the app's language at
launch from `AppleLanguages`, so a language change can't take effect on
the fly — the picker is upfront about that and offers
`AppLanguage.relaunch()` (opens a fresh copy of the app and quits the
current one).

`AppLanguage.launchedWith` records the language the process actually
started with — comparing against it is what keeps the relaunch warning
from showing unless switching the language would genuinely change
something (toggling back and forth within one session shouldn't nag the
user for no reason).

## Icons and branding

Double Bubble's own app icon has two themes, both drawn by
[`Scripts/make_app_icon.py`](../Scripts/make_app_icon.py) from one set of
geometry so they cannot drift apart. The dark mark is not the light one with
an inverted plate: it keeps the *relationships* that make the mark legible —
the two discs stay 43 points of luma apart, which is what stops them reading
as a single blob at 16pt, and the weaker disc keeps roughly the same contrast
against its plate that the lighter disc has on cream. The plate is a warm
near-black; neutral grey under terracotta reads as a different brand.

The dark version is applied at runtime by
[`DockIcon.swift`](../DoubleBubble/Services/DockIcon.swift), not by the asset
catalogue. A `.appiconset` has no slot for a dark macOS app icon — adding
`appearances: luminosity/dark` entries builds without error, which makes it
look like it worked, but `actool` reports the images as "unassigned children"
and drops them, and `assetutil` on the built `Assets.car` shows every AppIcon
entry with no appearance at all. The format that does carry one, Icon
Composer's `.icon`, is layered: it hands shape, shadow and material to macOS,
which would restyle the light mark rather than only add a dark one. Assigning
`NSApp.applicationIconImage` keeps the drawing exactly as designed and works
on every macOS the app supports; the trade is that it only applies while the
app is running, since nothing but the bundle can speak for it when it isn't.

Separate from the app's own appearance themes — branding the Dock icons
of running copies is covered in
[LAUNCH_ENGINE.md](LAUNCH_ENGINE.md#bundlecopy--copy--re-sign) and
implemented in
[`IconFactory.swift`](../DoubleBubble/Services/IconFactory.swift): a
colored circular badge with an initial or a custom picture, placed over
the bottom-right corner of the app's original icon, fitted to the
artwork's actual measured bounds (not the nominal square canvas — different
apps leave different margins inside their `.icns`).
