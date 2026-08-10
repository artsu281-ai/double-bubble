# LaunchEngine — как запускается вторая копия

[`LaunchEngine.swift`](../DoubleBubble/Services/LaunchEngine.swift) (962
строки) — ядро Double Bubble. Всё остальное приложение — это UI и
персистентность вокруг вопроса «как заставить второй экземпляр этого
конкретного `.app` запуститься со своими данными».

## Проблема

macOS обычно не даёт запустить второй экземпляр одного приложения: клик по
Dock-иконке активирует уже запущенный процесс вместо старта нового, а даже
там, где второй процесс всё же стартует, оба экземпляра по умолчанию читают
один и тот же профиль/конфиг/сессию. Единого универсального способа обойти
это для всех приложений не существует — разные технологии (Electron,
JetBrains Platform, обычные Cocoa-бандлы, песочница App Sandbox) требуют
разных трюков. `LaunchEngine` инкапсулирует пять таких трюков за одним
API.

## Пять стратегий (`LaunchStrategy`)

| Стратегия | Как работает | Для чего |
|---|---|---|
| `.electronFlag(binaryPath:)` | Запускает **оригинальный** бинарник напрямую с `--user-data-dir=<путь>` | Electron/Chromium-приложения, у которых нельзя сделать копию (library validation) |
| `.jetbrains(binaryPath:)` | Запускает оригинальный бинарник с `IDEA_PROPERTIES=<файл .properties>` в окружении | IntelliJ-платформа (IDEA, PyCharm, WebStorm, GoLand, RustRover, Rider, CLion) |
| `.configDir(binaryPath:flag:separateValue:)` | Запускает оригинальный бинарник с произвольным флагом конфиг-директории | Приложения со своим CLI-флагом (Zed: `--config-dir=`, Telegram Desktop: `-workdir`) |
| `.bundleCopy` | Копирует весь `.app`, патчит `CFBundleIdentifier`/`CFBundleDisplayName` в его `Info.plist`, переподписывает ad-hoc, запускает копию | «Нативные» Cocoa-приложения без флага для указания данных |
| `.copyThenFlag(flag:separateValue:)` | Комбинация: копирует и переподписывает бандл, затем запускает **копию** с флагом данных | Приложения в песочнице, которым флаг данных не помогает, пока они в песочнице (переподпись снимает entitlement) |

`displayName`, `label`, `symbolName`, `explanation` — это то же самое
перечисление, но с текстом/иконкой для UI (бейджи в карточке приложения).

## Как определяется стратегия

`detectStrategy(for:)` — чистая функция без побочных эффектов, порядок
проверок:

1. **База знаний** ([`AppKnowledgeBase`](KNOWLEDGE_BASE.md)) по
   `CFBundleIdentifier` — самый специфичный источник, побеждает всегда.
2. **Автоопределение Chromium-семейства** — по наличию
   `Contents/Frameworks/<Имя> Framework.framework` рядом с `Helpers/`.
   Проверка по layout фреймворка, а не по списку известных имён: жёстко
   зашитые «Google Chrome Framework.framework» + «Microsoft Edge
   Framework.framework» пропускали бы любую малоизвестную сборку на том же
   движке.
3. **Автоопределение JetBrains** — по наличию `Contents/jbr` (встроенный
   JetBrains Runtime).
4. Если ничего не подошло — фолбэк `.bundleCopy`.

## Проверки перед запуском

Прежде чем реально копировать/подписывать бандл, `LaunchEngine` спрашивает
у `codesign`:

- **`sandboxInfo(for:)`** — читает entitlements (`codesign -d
  --entitlements :-`). Если приложение в App Sandbox **и** использует
  `application-groups` — `SandboxInfo.blocksBundleCopy == true`: переподпись
  ad-hoc теряет Team ID, из-за чего копия физически не может достучаться до
  App Group своих же данных. Копировать такое приложение — гарантированно
  сломанная вторая копия, поэтому запуск прерывается заранее с понятной
  ошибкой (`LaunchError.sandboxedAppGroup`), вместо того чтобы дать
  пользователю наткнуться на битую копию самому.
- **`usesLibraryValidation(for:)`** — парсит вывод `codesign -dv` на предмет
  `library-validation`. Такой бандл после ad-hoc переподписи вообще
  отказывается запускаться («Не удаётся открыть приложение», без вменяемой
  причины от системы) — это все Chromium-браузеры. Тоже блокируется заранее
  (`LaunchError.libraryValidation`).

Обе проверки закэшированы в `AppLibrary` (`sandboxCache`,
`libraryValidationCache`) — `codesign` это внешний процесс, вызывать его на
каждый рендер SwiftUI-вьюхи недопустимо.

## Пошагово: что происходит при `launch(...)`

```
launch(appURL:appName:account:distinctIcons:)
  │
  ├─ детектит strategy
  ├─ если distinctIcons включён и апгрейд возможен → апгрейдит стратегию
  │    (electronFlag/configDir → copyThenFlag, см. ниже)
  ├─ если account.usesDefaultProfile → всегда launchElectron(..., userDataDir: nil)
  │    (своя обёртка/иконка, но без изоляции данных — см. DATA_MODEL.md)
  └─ иначе — switch по strategy:
       .electronFlag   → launchElectron(...)
       .jetbrains      → launchJetBrains(...)
       .configDir      → launchConfigDir(...)
       .bundleCopy     → (после проверок sandbox/library-validation) launchViaBundleCopy(...)
       .copyThenFlag   → (после тех же проверок) launchViaBundleCopy(..., workdir: ...)
```

### `.electronFlag` — обёртка вокруг оригинального бинарника

Собирается минимальный `.app`-«стаб» в
`~/.double_bubble/bundles/<slug>-<key>/<ИмяАккаунта>.app`:

```
Contents/
  Info.plist          — уникальный CFBundleIdentifier + CFBundleDisplayName
  MacOS/launcher       — shell-скрипт: exec "<реальный бинарник>" --user-data-dir=<путь> "$@"
  Resources/icon.icns  — брендированная иконка (IconFactory)
```

`exec` в скрипте — не случайность: с точки зрения ядра процесс *становится*
реальным Chrome/VS Code в момент `exec`, а не остаётся дочерним процессом
обёртки. Это буквально те же килобайты, а не гигабайты — оригинальный
бандл не копируется и не трогается вовсе, поэтому обходится даже
library-validation (никакая переподпись оригинального кода не требуется).

### `.jetbrains` — переменная окружения `IDEA_PROPERTIES`

Создаёт `~/.double_bubble/data/<slug>-<key>/{config,system,plugins,logs}` и
файл `idea.properties`, указывающий платформе на эти папки. Оригинальный
бинарник запускается напрямую (`Process`), с этой переменной в окружении.
Полная изоляция: конфиг, кэши, установленные плагины, логи — всё раздельно.

### `.configDir` — произвольный CLI-флаг

Аналогично, но параметризовано: флаг (`--config-dir`, `-workdir`, ...) и
форма аргумента — `separateValue: true` даёт два отдельных argv-элемента
(`-workdir /path`, как ожидает Qt/Telegram Desktop), `false` — одну строку
GNU-style (`--config-dir=/path`).

### `.bundleCopy` — копия + переподпись

1. Копирует весь `.app` в `~/.double_bubble/bundles/<slug>-<key>/`.
2. `xattr -rd com.apple.quarantine` — иначе Gatekeeper снова спросит
   подтверждение на «скачанное» приложение при первом запуске копии.
3. Патчит `Contents/Info.plist`: `CFBundleIdentifier` получает суффикс
   `.doublebubble.<isolationKey>`, `CFBundleDisplayName` — имя аккаунта.
   Уникальный bundle ID — это то, что вообще позволяет двум копиям
   сосуществовать как раздельные Dock-иконки и раздельные LaunchServices-
   записи.
4. Брендирует иконку через `IconFactory.brand(...)` **до** подписи —
   изменение ресурсов бандла после подписи инвалидирует сигнатуру.
   Ошибка брендирования не прерывает запуск — это чисто косметика.
5. Переподписывает ad-hoc (`codesign --force --sign - --deep`), включая все
   вложенные `Frameworks`/`PlugIns` по отдельности перед финальной подписью
   верхнего уровня.
6. Открывает копию через `NSWorkspace.openApplication` с
   `createsNewApplicationInstance = true`.

### `.copyThenFlag` — копия, которой затем даётся флаг

То же самое копирование/переподпись, но вместо `NSWorkspace.openApplication`
копия запускается напрямую через `Process` с флагом данных, указывающим на
свою директорию в `~/.double_bubble/data/...`. Нужен для приложений,
которые в песочнице *принимают* флаг рабочей директории, но реально
использовать его не могут, пока в песочнице — переподпись снимает
sandbox-entitlement, и только тогда флаг начинает работать (иначе обе
копии продолжали бы падать в общий системный support-каталог и вторая
завершалась бы из-за файловой блокировки первой).

## Апгрейд до различающихся иконок

`LaunchEngine.upgradedForDistinctIcons(_:)` переписывает флаговую стратегию
в её «копийного близнеца»:

```
.electronFlag        → .copyThenFlag(flag: "--user-data-dir", separateValue: false)
.configDir(_, f, sv)  → .copyThenFlag(flag: f, separateValue: sv)
.jetbrains/.bundleCopy/.copyThenFlag → без изменений
```

Логика: отдельная Dock-иконка физически может жить только в отдельном
бандле — без копии есть только оригинальный `.app`, который брендировать
нельзя, не сломав его для всех остальных запусков. `supportsDistinctIconsUpgrade`
и `canUpgradeForDistinctIcons(appURL:strategy:)` определяют, когда такой
апгрейд вообще имеет смысл предлагать в UI (стратегия это поддерживает
*и* бандл технически копируем — не library-validated).

## Обнаружение уже запущенных копий (`discoverRunningInstances`)

При старте Double Bubble не помнит `pid` предыдущей сессии (`AppInstance`
не персистится), поэтому ищет их заново по двум источникам:

1. **Копийные стратегии** — `NSWorkspace.shared.runningApplications`,
   фильтр по `bundleURL`, начинающемуся с
   `~/.double_bubble/bundles/`. `isolationKey` вычленяется прямо из пути.
2. **Флаговые стратегии** (оригинальный бинарник, свой процесс) —
   `ps -axo pid=,args=`, поиск подстроки `~/.double_bubble/data/` в
   аргументах командной строки. Дочерние процессы Electron (`--type=...`
   для renderer/gpu/utility) явно исключаются — иначе `terminate()`
   получил бы pid хелпер-процесса, а не главного, и приложение осталось бы
   жить.

Оба пути возвращают словарь `isolationKey → RunningInstance(pid, url,
launchedAt)`, который `AppLibrary.adoptRunningInstances()` сопоставляет
обратно с сохранёнными `Account` по их `isolationKey`.

## Остановка (`terminate(instance:)`)

- Снимает регистрацию из `ProcessMonitor`.
- `NSRunningApplication(processIdentifier:)?.terminate()`, либо
  `kill(pid, SIGTERM)`, если система не знает про такой `NSRunningApplication`
  (характерно для процессов, запущенных напрямую через `Process`, а не
  через `NSWorkspace`).
- Для `electronFlag` — обёртка (килобайты, пересобирается тривиально)
  удаляется с диска спустя 3 секунды.
- Для `bundleCopy`/`copyThenFlag` копия **намеренно не удаляется**. Раньше
  удалялась точно так же, как обёртка — но копия каждый раз пересобиралась и
  переподписывалась ad-hoc заново, из-за чего macOS считала её новым
  приложением: любое разрешение Screen Recording/Accessibility, выданное
  этой копии в System Settings, переставало действовать после первого же
  Stop → Open, хотя галочка в настройках оставалась включённой. Теперь копия
  остаётся на диске между запусками, а `launchViaBundleCopy` переиспользует
  её как есть, если ничего, что влияет на её содержимое, не изменилось —
  см. [ниже](#переиспользование-копии-между-запусками). Уборка мусора для
  копий, чей аккаунт реально удалён из библиотеки, по-прежнему происходит,
  но через `cleanUpOrphanedBundles(keeping:)` при следующем старте Double
  Bubble, а не немедленно после Stop.
- Для `jetbrains`/`configDir` ничего не удаляется — там нет отдельного
  «бандла-копии», всё это и есть данные аккаунта.

## Переиспользование копии между запусками

`launchViaBundleCopy` перед тем, как удалить и пересобрать `accountDir`,
проверяет **отпечаток** (`copyFingerprint(appURL:account:)`) — строку из
версии исходного приложения (`LaunchEngine.bundleVersion(at:)`), имени
аккаунта, его цвета и SHA-256 его картинки (если есть). Отпечаток пишется в
скрытый файл `.doublebubble-fingerprint` рядом с копией **только после**
успешного завершения копирования, патча `Info.plist`, брендирования иконки
и переподписи — то есть само его наличие с совпадающим содержимым уже
гарантирует, что копия целиком собрана и подписана корректно.

Если файл существует и совпадает с текущим отпечатком — копия
переиспользуется как есть, без единого вызова `codesign`: та же подпись, тот
же bundle ID, та же identity, на которую могли быть выданы системные
разрешения. Пересборка запускается только когда реально изменилось то, что
в копию попадает: обновилась версия исходного приложения, либо у аккаунта
поменялись имя/цвет/картинка (что патчится в `Info.plist`/иконку копии).
Поля вроде `lastOpenedAt` в отпечаток намеренно не входят — иначе пересборка
происходила бы на каждый запуск, что как раз и было проблемой.

## Файловая структура на диске

```
~/.double_bubble/
├── bundles/
│   └── <slug>-<isolationKey>/
│       └── <Имя>.app            # копия или .app-обёртка, пересоздаётся при каждом запуске
└── data/
    └── <slug>-<isolationKey>/   # config/system/plugins/logs (JetBrains) или user-data-dir
```

`slug` — `LaunchEngine.slug(for:)`, безопасное для файловой системы имя
приложения (небезопасные символы → `_`). `isolationKey` — первые 8 hex
символов UUID аккаунта в нижнем регистре
(см. [DATA_MODEL.md](DATA_MODEL.md#account)).

Уборка мусора (см. [ARCHITECTURE.md](ARCHITECTURE.md)) при каждом старте
приложения:

- `cleanUpOrphanedBundles(keeping:)` — удаляет папки в `bundles/`, которые
  не запущены сейчас, не закреплены в Dock (закреплённая, но не запущенная
  копия всё равно «используется» — удаление превратило бы её тайл в Dock в
  знак вопроса) **и** чей `isolationKey` не принадлежит ни одному аккаунту,
  всё ещё сохранённому в библиотеке. Последнее условие — то, что раньше
  отсутствовало: без него копия для существующего, просто сейчас не
  запущенного аккаунта сносилась бы при каждом перезапуске Double Bubble,
  и все выданные ей системные разрешения приходилось бы получать заново.
- `cleanUpOrphanedData(keeping:)` — трэшит папки в `data/`, чей
  `isolationKey` не встречается ни у одного сохранённого аккаунта. Строго
  проверяет форму имени (`<slug>-<8 hex>`), чтобы ничего постороннего,
  случайно положенного пользователем в этот каталог руками, не было
  затронуто.

## Ошибки (`LaunchError`)

| Case | Когда | Сообщение пользователю |
|---|---|---|
| `.noAppSelected` | у `ManagedApp` не разрешился `URL` | приложение не выбрано |
| `.plistReadFailed` | `Info.plist` копии не читается | не удалось прочитать `Info.plist` |
| `.launchFailed` | `Process`/`NSWorkspace` вернули ошибку или процесс не поднялся | «системные и жёстко изолированные приложения могут не работать» |
| `.sandboxedAppGroup` | `sandboxInfo(for:).blocksBundleCopy` | подробное объяснение про App Group + entitlement, см. код |
| `.libraryValidation` | `usesLibraryValidation(for:)` | объяснение + подсказка добавить приложение в базу знаний с флаговой стратегией, если оно его поддерживает |
