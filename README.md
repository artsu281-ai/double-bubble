# Double Bubble

Нативное macOS-приложение (SwiftUI + AppKit), которое позволяет запускать
**несколько изолированных копий одного и того же приложения одновременно** —
например, два аккаунта Slack, Telegram, Chrome или JetBrains IDE, каждый в
своём Dock-значке, со своим именем, цветом и (по возможности) собственной
иконкой.

Идея названа в честь того, как выглядит одна клетка, делящаяся на две —
именно это движение показывает фирменный знак приложения
([`BubbleMark`](DoubleBubble/Views/Components/BubbleMark.swift)).

Разработчик: **ConstantaAI**, © 2026. Bundle ID — `com.doublebubble.app`.

**→ Просто хотите пользоваться приложением?** Начните с
[docs/USER_GUIDE.md](docs/USER_GUIDE.md) — там установка, первый запуск и
разбор частых вопросов простым языком, без деталей реализации.

## Возможности

- Запуск двух и более аккаунтов одного приложения параллельно, без
  переключения профиля внутри самого приложения.
- Автоматическое определение способа изоляции данных под конкретное
  приложение (Electron, JetBrains, «нативные» бандлы и т. д.) — см.
  [docs/LAUNCH_ENGINE.md](docs/LAUNCH_ENGINE.md).
- Встроенная база знаний о десятках популярных приложений (браузеры,
  мессенджеры, IDE, дизайн-инструменты) с готовыми стратегиями изоляции —
  см. [docs/KNOWLEDGE_BASE.md](docs/KNOWLEDGE_BASE.md).
- Опциональные различающиеся иконки в Dock (цветной бейдж с инициалом или
  своей картинкой) для аккаунтов, которые физически невозможно отличить
  друг от друга иначе.
- Отслеживание запущенных копий в реальном времени, переподключение к ним
  после перезапуска Double Bubble, предупреждение при попытке выйти из
  приложения при живых процессах.
- Menu Bar Extra для быстрого запуска/остановки аккаунтов без открытия
  главного окна.
- Локализация RU/EN, тема оформления (Terracotta/Light/Dark/System),
  два уровня плотности интерфейса.

## Требования

- macOS 14.0+ (Sonoma) — как для сборки, так и для запуска.
- Xcode 16.0+, Swift 5.10.
- Опционально: [XcodeGen](https://github.com/yonaskolb/XcodeGen), если нужно
  перегенерировать `DoubleBubble.xcodeproj` из [`project.yml`](project.yml).

## Сборка и запуск

Основной способ — через Xcode:

```bash
open "DoubleBubble.xcodeproj"
```

Дальше — обычный ⌘R. Проект собирается как приложение (`.app`), подпись —
`Automatic` с `CODE_SIGN_IDENTITY = "-"` (ad-hoc), команда разработки не
задана, так что сборка работает без Apple Developer аккаунта.

Если менялся [`project.yml`](project.yml) (цели, настройки, Info.plist) —
`.xcodeproj` нужно перегенерировать:

```bash
xcodegen generate
```

`Package.swift` в корне существует только для того, чтобы Swift-инструментам
в IDE (автодополнение, `swift build` для проверки компиляции) было на что
опереться — реальная сборка приложения всегда идёт через `.xcodeproj`,
не через SwiftPM.

```bash
swift build
```

## Структура проекта

```
DoubleBubble/
├── DoubleBubbleApp.swift        # Точка входа, Scene, MenuBarExtra, AppDelegate
├── Models/
│   ├── ManagedApp.swift         # ManagedApp, Account — основная модель данных
│   ├── AppInstance.swift        # Запись о запущенном процессе
│   ├── AppLibrary.swift         # ObservableObject: вся бизнес-логика библиотеки
│   └── Profile.swift            # Легаси-модель (для миграции со старой версии)
├── Services/
│   ├── LaunchEngine.swift       # Ядро: как именно запускается вторая копия
│   ├── AppKnowledgeBase.swift   # База знаний о приложениях
│   ├── IconFactory.swift        # Генерация брендированных .icns
│   ├── ProcessMonitor.swift     # Отслеживание живых процессов
│   ├── AccountIcon.swift        # Загрузка/нормализация своей картинки аккаунта
│   ├── NotificationService.swift# Уведомления об ошибке запуска
│   ├── AppTheme.swift           # Темы оформления и палитра
│   ├── AppLanguage.swift        # Переключение языка интерфейса
│   ├── InterfaceDensity.swift   # Comfortable / Compact режимы плотности
│   ├── LaunchAtLogin.swift      # Обёртка над SMAppService
│   └── DiskUsage.swift          # Подсчёт размера папки на диске
├── Views/
│   ├── LibraryView.swift        # Главный экран: сайдбар + деталка + карточки
│   ├── AccountEditorView.swift  # Редактор имени/цвета/иконки аккаунта
│   ├── AboutSettingsView.swift  # Окно настроек (Язык/Интерфейс/Общие/О программе)
│   └── Components/BubbleMark.swift # Анимированный фирменный знак
├── Assets.xcassets/             # Иконка приложения, логотип издателя
├── Localizable.xcstrings        # RU/EN строки
├── Info.plist / DoubleBubble.entitlements
Scripts/
├── make_app_icon.py             # Генерация AppIcon.icns из исходника
_Archive/                        # Черновики более ранних версий UI (не используются в сборке)
```

## Документация

- [docs/USER_GUIDE.md](docs/USER_GUIDE.md) — руководство пользователя:
  установка, первый запуск, частые вопросы. Начните отсюда, если просто
  хотите пользоваться приложением.

Подробное описание архитектуры и подсистем — в каталоге [`docs/`](docs/):

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — как всё связано между собой,
  жизненный цикл приложения, поток данных.
- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) — модели данных, персистентность,
  миграция со старой версии.
- [docs/LAUNCH_ENGINE.md](docs/LAUNCH_ENGINE.md) — как запускается вторая
  копия приложения: стратегии изоляции, песочница, подпись, файловая
  структура `~/.double_bubble`.
- [docs/KNOWLEDGE_BASE.md](docs/KNOWLEDGE_BASE.md) — база знаний о конкретных
  приложениях и как добавить в неё новое.
- [docs/UI.md](docs/UI.md) — экраны, темы оформления, локализация,
  плотность интерфейса.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Screen
  Recording/Accessibility для изолированных копий: почему разрешения
  привязаны к конкретной копии, как их выдавать и как чинить «залипшие»
  записи в System Settings.

## Где живут данные аккаунтов

Double Bubble ничего не пишет внутрь `~/Library` целевого приложения.
Все изолированные копии и данные аккаунтов лежат в:

```
~/.double_bubble/
├── bundles/   # копии .app-бандлов (bundleCopy) и .app-обёртки (electronFlag)
└── data/      # изолированные data/config-директории (electronFlag, jetbrains, configDir, copyThenFlag)
```

Настройки самого Double Bubble (список приложений и аккаунтов, тема, язык,
плотность) хранятся в `UserDefaults` под ключом `com.doublebubble.library`
(подробнее — [docs/DATA_MODEL.md](docs/DATA_MODEL.md)).

## Поддержать проект

Если Double Bubble оказался полезен и хочется поддержать разработку —
принимаются донаты в крипте:

| Сеть | Адрес |
|---|---|
| USDT (TRC20) | `TJhS247LSsQqCW7174WR5rbbSFxRDbTpih` |
| TON | `UQBvWb4ezuNazeLxVq8jd51FWokmmCRlkWyfg0WeQVe2_9UK` |
| Solana | `GCXiFb73Zw6QzkxvtqPjkUhditMYLRRS6SdrPug8GcZf` |
| Ethereum | `0x799FA0D3ec0aA876D5ADeBB4c7FFDC64431c42f7` |

Перед переводом сверьте адрес и сеть в своём кошельке — перевод не в ту
сеть невозвратен.

## Известные ограничения

- Приложения с library validation в подписи (все Chromium-браузеры) нельзя
  запустить из пересобранной копии — macOS отказывается её открывать.
  Для них используется прямой флаг `--user-data-dir` на оригинальном
  бинарнике, поэтому у второй копии не может быть отдельной Dock-иконки.
- Приложения в песочнице с общими App Groups (например, нативный Telegram
  для macOS) в принципе не могут быть скопированы и переподписаны — копия
  потеряет доступ к своим же данным. Для таких Double Bubble заранее
  показывает предупреждение и, если есть, предлагает альтернативную сборку.
