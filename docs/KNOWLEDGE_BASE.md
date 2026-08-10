# AppKnowledgeBase — база знаний о приложениях

[`AppKnowledgeBase.swift`](../DoubleBubble/Services/AppKnowledgeBase.swift)
— статический реестр `[(bundleID-префикс, IsolationDescriptor)]`,
описывающий, каким способом лучше всего изолировать данные для конкретных,
заранее известных приложений. Это первый и самый приоритетный источник для
`LaunchEngine.detectStrategy(for:)` — специфичное знание побеждает любую
автоэвристику (см. [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md#как-определяется-стратегия)).

Составлено (согласно комментарию в исходнике) по публичной документации,
документации Electron/JetBrains и общеизвестным практикам сообщества — без
копирования кода из сторонних проектов.

## `IsolationDescriptor`

```swift
struct IsolationDescriptor {
    enum Kind {
        case electronUserDataDir
        case jetbrainsVMOptions
        case configDir(flag: String, separateValue: Bool)
        case bundleCopy
        case copyThenFlag(flag: String, separateValue: Bool)
    }
    let kind: Kind
    let description: String     // человекочитаемое описание для UI
    let persistsData: Bool      // сохраняются ли данные между сессиями
    var requiresOriginalBundle: Bool = false
}
```

`requiresOriginalBundle` — отдельный, самый жёсткий флаг: приложение
обязано запускаться только из исходного бандла, копия для него в принципе
недопустима (типичный случай — Chromium-браузеры с library validation,
у которых launcher ре-исполняется через сам бандл и теряет переданный
argv). Это ограничение, с которым обязана считаться Dock-иконка с
собственным брендом: без копии просто негде разместить брендированную
иконку, и рабочий второй профиль важнее красивого тайла.

## Текущий реестр (кратко)

| Приложение | Bundle ID (префикс) | Стратегия | Примечание |
|---|---|---|---|
| Claude Desktop | `com.anthropic.claudefordesktop` | `copyThenFlag(--user-data-dir)` | Keychain access group завязана на Team ID — простого `--user-data-dir` недостаточно, нужна ещё и переподпись |
| ChatGPT Desktop | `com.openai.chat` | `electronUserDataDir` | |
| Cursor | `com.todesktop.230313mzl4w4u92` | `electronUserDataDir` | |
| Windsurf | `com.exafunction.windsurf` | `electronUserDataDir` | |
| VS Code | `com.microsoft.VSCode` / `com.microsoft.vscode` | `electronUserDataDir` | |
| Zed | `dev.zed.zed` | `configDir(--config-dir, false)` | |
| IntelliJ / PyCharm / WebStorm / GoLand / RustRover / Rider / CLion | `com.jetbrains.*` | `jetbrainsVMOptions` | |
| Slack | `com.tinyspeck.slackmacgap` | `electronUserDataDir` | у Slack есть и штатный переключатель воркспейсов — см. ниже |
| Discord | `com.discord` / `com.hnc.Discord` | `electronUserDataDir` | |
| Telegram для macOS (нативный) | `ru.keepcoder.Telegram` | `bundleCopy` | Sandboxed + App Group ⇒ копия не изолируется (см. [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md)); есть встроенный мультиаккаунт и рабочая альтернатива |
| Telegram Desktop (App Store) | `org.telegram.desktop` | `copyThenFlag(-workdir, true)` | Sandboxed, но без App Group — переподпись безопасна |
| Telegram Desktop (сайт) | `com.tdesktop.Telegram` | `configDir(-workdir, true)` | Не sandboxed — копия вообще не нужна |
| Chrome / Edge / Brave / Vivaldi / Opera / Yandex Browser | `com.google.Chrome` и т. д. | `electronUserDataDir`, `requiresOriginalBundle: true` | Library validation — копия невозможна в принципе |
| Arc | `company.thebrowser.Browser` | `electronUserDataDir` | |
| Figma | `com.figma.desktop` | `electronUserDataDir` | |
| Linear | `com.linear` | `electronUserDataDir` | |
| Notion | `notion.id` | `electronUserDataDir` | |
| Spotify | `com.spotify.client` | `bundleCopy` | |

Полный и всегда актуальный список — сам файл
[`AppKnowledgeBase.swift`](../DoubleBubble/Services/AppKnowledgeBase.swift),
таблица выше может отставать от кода.

## Подсказки вместо изоляции

Для двух категорий заблокированных случаев `AppKnowledgeBase` отвечает не
стратегией, а готовой человекочитаемой подсказкой:

- **`builtInMultiAccountHint(forBundleID:)`** — приложение уже само умеет
  несколько аккаунтов (Telegram для macOS: «Settings → имя → Add
  Account»; Slack: переключатель воркспейсов в сайдбаре). Когда Double
  Bubble не может изолировать такое приложение, указать на встроенную
  функцию полезнее, чем объяснять проблему с подписью кода.
- **`alternative(forBundleID:)`** — существует другая сборка того же
  продукта, которую Double Bubble изолировать *может*. Мотивирующий
  пример — Telegram: нативный клиент заблокирован App Group, а Telegram
  Desktop хранит всё в обычной папке. `AppLibrary.installedAlternative(for:)`
  проверяет, установлена ли такая сборка на диске и ещё не добавлена в
  библиотеку, и если да — предлагает добавить её одним кликом вместо
  объяснения проблемы с подписью.

## Как добавить новое приложение

1. Узнать `CFBundleIdentifier` приложения:
   ```bash
   defaults read "/Applications/Имя.app/Contents/Info.plist" CFBundleIdentifier
   ```
2. Определить механизм изоляции данных:
   - Electron/Chromium с library validation → `electronUserDataDir`
     (+ `requiresOriginalBundle: true`, если приложение отказывается
     запускаться из копии — проверить: `codesign -dv /Applications/Имя.app
     2>&1 | grep library-validation`).
   - JetBrains Platform → `jetbrainsVMOptions`.
   - Есть собственный CLI-флаг конфиг-директории → `configDir(flag:,
     separateValue:)`. `separateValue: true`, если флаг ожидает значение
     отдельным аргументом (`-workdir /path`), `false` — для `--flag=value`.
   - Ничего из вышеперечисленного, обычный Cocoa-бандл → `bundleCopy`
     (это и есть безопасный дефолт при отсутствии записи в базе).
   - Sandboxed-приложение, принимающее CLI-флаг, но требующее снятия
     sandbox-entitlement, чтобы флаг реально сработал → `copyThenFlag`.
3. Проверить sandbox/App Group **до** добавления записи с `bundleCopy`/
   `copyThenFlag`:
   ```bash
   codesign -d --entitlements :- /Applications/Имя.app
   ```
   Если есть `com.apple.security.app-sandbox = true` **и**
   `com.apple.security.application-groups` непустой — копирование в
   принципе не сработает; такое приложение либо не добавлять в реестр
   вовсе (сработает fallback-блокировка в `LaunchEngine` с понятной
   ошибкой), либо поискать альтернативную сборку и добавить через
   `alternative(forBundleID:)`.
4. Добавить запись в `AppKnowledgeBase.registry`, соблюдая порядок «от
   более специфичного префикса к менее специфичному» (поиск —
   `hasPrefix`, первое совпадение побеждает).
5. Проверить реальным запуском: добавить приложение в Double Bubble,
   открыть два аккаунта, убедиться, что оба поднимаются одновременно и не
   делят сессию/логин.
