# Архитектура

## Общая картина

Double Bubble — классическое SwiftUI-приложение с одним источником истины
и без сетевого слоя: всё состояние живёт локально, на диске и в памяти
процесса.

```
DoubleBubbleApp (Scene)
   │
   ├── LibraryView (главное окно)
   ├── MenuBarMenuView (иконка в строке меню)
   │
   └── AppLibrary  ── единственный @StateObject, общий для обоих экранов
          │
          ├── ManagedApp / Account   (что и с кем сохранено)
          ├── AppInstance             (что сейчас реально запущено, в памяти)
          │
          ├── LaunchEngine.shared     (как запустить/остановить копию)
          │      └── AppKnowledgeBase (какую стратегию изоляции применить)
          │      └── IconFactory      (брендирование Dock-иконки)
          │
          └── ProcessMonitor.shared   (жив ли ещё процесс с данным pid)
```

`AppLibrary` — это одновременно и модель данных (`@Published var apps`), и
контроллер, дергающий `LaunchEngine`/`ProcessMonitor`. Отдельного слоя
ViewModel нет: вьюхи ([`LibraryView.swift`](../DoubleBubble/Views/LibraryView.swift))
работают с `AppLibrary` напрямую как с `@ObservedObject`.

## Жизненный цикл приложения

Точка входа — [`DoubleBubbleApp.swift`](../DoubleBubble/DoubleBubbleApp.swift):

- `Window("Double Bubble", id: "main")` — единственное окно приложения,
  показывает `LibraryView`.
- `MenuBarExtra` — второй, независимый UI поверх того же `AppLibrary`:
  список аккаунтов со статусом «запущен/нет» и кнопками Open/Stop прямо из
  строки меню, без необходимости открывать окно.
- Настроек-сцены (`Settings {}`) нет намеренно: настройки живут в поповере
  тулбара главного окна, чтобы `⌘,` не создавал второе окно с тем же
  функционалом.
- `AppDelegate` перехватывает `applicationShouldTerminate` — единственный
  способ на AppKit узнать «а можно ли вообще выходить прямо сейчас».
  SwiftUI Scene-жизненный цикл такого хука не даёт. Если у `library` есть
  хоть один запущенный аккаунт, показывается предупреждение: выход не
  убивает эти процессы, они продолжат работать в фоне, а Double Bubble
  переподключится к ним при следующем запуске.

## Поток данных: запуск аккаунта

1. Пользователь жмёт «Open» на карточке аккаунта в
   [`AccountCard`](../DoubleBubble/Views/LibraryView.swift) (или в
   `MenuBarMenuView`).
2. Вызывается `AppLibrary.open(account:in:)`:
   - если для этого `account.id` уже есть живой `AppInstance` — выходим
     сразу (идемпотентность повторного клика);
   - если запись есть, но процесс на самом деле мёртв — она вычищается,
     чтобы не блокировать повторный запуск;
   - резолвится security-scoped bookmark приложения в `URL`;
   - `LaunchEngine.shared.launch(appURL:appName:account:distinctIcons:)`
     определяет стратегию изоляции и физически запускает процесс —
     подробности в [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md);
   - результат (`AppInstance` с `pid`) кладётся в `instances[account.id]`;
   - `lastOpenedAt` аккаунта обновляется и сохраняется;
   - `bringForward(_:)` несколько раз с интервалом активирует процесс по
     `pid` — обёрнутый процесс отвечает на тот же bundle ID, что и уже
     запущенный оригинал, поэтому активация «вообще каким-нибудь окном»
     системой может подсунуть не тот аккаунт, если не указать pid явно.
3. `ProcessMonitor` узнаёт о смерти процесса тремя параллельными путями
   (уведомления `NSWorkspace`, `Process.terminationHandler`, поллинг
   `kill(pid, 0)` раз в 5с) и обновляет `@Published runningPIDs`.
4. `AppLibrary` подписан на этот поток и через `pruneDeadInstances()`
   убирает из `instances` записи о процессах, которых больше нет — включая
   случай, когда пользователь закрыл вторую копию вручную через `⌘Q`.

## Персистентность и восстановление состояния

- Список `apps: [ManagedApp]` сохраняется в `UserDefaults` (JSON) при каждом
  изменении (`didSet { save() }`). Подробности модели — в
  [DATA_MODEL.md](DATA_MODEL.md).
- `instances: [UUID: AppInstance]` — **только в памяти**. При перезапуске
  Double Bubble список обнуляется и восстанавливается заново через
  `adoptRunningInstances()`, которая вызывает
  `LaunchEngine.discoverRunningInstances()` — сканирует запущенные
  приложения (`NSWorkspace.runningApplications`) и вывод `ps -axo pid=,args=`
  в поисках путей вида `~/.double_bubble/{bundles,data}/<slug>-<key>`,
  привязывая их обратно к `Account.isolationKey`.
- При старте `AppLibrary.init()` также вызывает уборку:
  `LaunchEngine.shared.cleanUpOrphanedBundles(keeping:)` (удаляет
  скопированные бандлы, которые не запущены, не закреплены в Dock и не
  принадлежат ни одному оставшемуся в библиотеке аккаунту) и
  `cleanUpOrphanedData(keeping:)` (в Trash улетают data-папки, для которых
  в библиотеке больше нет аккаунта). Копии для существующих аккаунтов
  специально переживают этот сброс — иначе System Settings продолжали бы
  показывать Screen Recording/Accessibility как выданные для копии, которой
  уже нет на диске; подробности — в
  [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md#переиспользование-копии-между-запусками).

## Слой сервисов

`Services/` группирует независимые друг от друга утилиты, каждая отвечает
за одну вещь:

| Сервис | Зона ответственности |
|---|---|
| [`LaunchEngine`](../DoubleBubble/Services/LaunchEngine.swift) | Запуск/остановка второй копии приложения — ядро проекта, см. [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md) |
| [`AppKnowledgeBase`](../DoubleBubble/Services/AppKnowledgeBase.swift) | Реестр «bundle ID → стратегия изоляции» для известных приложений |
| [`IconFactory`](../DoubleBubble/Services/IconFactory.swift) | Рендер брендированной `.icns` (оригинальная иконка + цветной бейдж) |
| [`ProcessMonitor`](../DoubleBubble/Services/ProcessMonitor.swift) | Единый источник истины «жив ли pid» для всего приложения |
| [`AccountIcon`](../DoubleBubble/Services/AccountIcon.swift) | Импорт и нормализация пользовательской картинки аккаунта (квадрат, ≤256px) |
| [`NotificationService`](../DoubleBubble/Services/NotificationService.swift) | Системные уведомления об ошибке запуска, когда нет открытого окна для алерта |
| [`AppTheme`](../DoubleBubble/Services/AppTheme.swift) | Темы оформления и `ThemePalette`, читаемая напрямую из вьюх через `Environment` |
| [`AppLanguage`](../DoubleBubble/Services/AppLanguage.swift) | Переопределение `AppleLanguages`, требует релонча |
| [`InterfaceDensity`](../DoubleBubble/Services/InterfaceDensity.swift) | Единый параметр размеров UI (Comfortable/Compact) |
| [`LaunchAtLogin`](../DoubleBubble/Services/LaunchAtLogin.swift) | Обёртка над `SMAppService` для автозапуска при входе в систему |
| [`DiskUsage`](../DoubleBubble/Services/DiskUsage.swift) | Асинхронный подсчёт размера папки на диске (для показа «сколько весит» аккаунт) |

Все сервисы — `enum` с статическими методами или синглтон `.shared`;
инъекции зависимостей и протоколов-абстракций в проекте нет — размер
кодовой базы (~4400 строк) её не оправдывает.

## Потокобезопасность

- `LaunchEngine` явно помечен `@unchecked Sendable`: у каждого аккаунта своя
  директория (ключ — `Account.isolationKey`), общего мутируемого состояния
  между параллельными запусками нет, поэтому запуск двух аккаунтов
  одновременно безопасен.
- `ProcessMonitor` сериализует доступ к внутреннему `[pid_t: Process]` через
  приватную `DispatchQueue`, а все мутации `@Published runningPIDs` уводит на
  главный поток — за одним намеренным исключением: если вызывающий уже на
  главном потоке, мутация применяется синхронно, чтобы не потерять «гонку»
  между регистрацией нового pid и запущенной в этом же тике проверкой на
  мёртвые инстансы (см. комментарий у `ProcessMonitor.mutate(_:)`).
