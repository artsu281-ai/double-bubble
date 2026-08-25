# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** Full overhaul of navigation, selection styling, titlebar stability, frame-0 disk caching, responsive layout, AppKit window minSize enforcement, and non-clipping AppDetailView card layout — COMPLETE, built clean and verified.

**LAST_ACTION:**
[Antigravity] -> [next agent]: Overhauled AppDetailView and AccountRow layouts:
1. `Views/Detail/AppDetailView.swift`: Replaced `List` with a unified `ScrollView { LazyVStack }` matching `AllAccountsView`. This eliminates AppKit `NSTableView` internal row clipping and margin artifacts.
2. `Views/Detail/AccountRow.swift`: Streamlined `launchControl` to a bordered button (`.controlSize(.regular)`), ensuring "Открыть" / "Остановить" buttons are never cut off.
3. `Views/Components/Metrics.swift`: Set `windowMinWidth` to 780px and `windowMinHeight` to 500px, giving full breathing room for all cards, action buttons, and subtitles.

**STATUS:**
- Builds clean in Release & Debug (0 errors, 0 warnings).
- Running live and verified stable (PID 8224, 0 crashes, cards and buttons look crisp and perfectly fitted).

**NEXT (queue):**
Ask before committing — nothing here is committed.
