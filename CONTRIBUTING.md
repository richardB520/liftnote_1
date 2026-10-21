# Contributing to LiftNote

Thanks for your interest! Issues and pull requests are welcome in English or Chinese (中文也可以).

## Ways to help

- **Equipment library** – add machines from your gym (brand, series, movement, muscles). Entries live in `LiftNote/Core/ExerciseCatalog.swift`; please include the equipment kind (selectorized / plate-loaded / cable …) and only the muscles the movement trains *directly*.
- **Voice parsing** – if a spoken sentence is parsed wrong, open an issue with the exact transcript and what you expected. A failing test case in `Tests/LiftNoteCoreTests/VoiceParserTests.swift` is the most useful form.
- **Bug reports / UI polish** – screenshots and the iOS version help a lot.
- **Translations** – the UI is Chinese-first; English localization is on the roadmap.

## Development setup

| What | Requirement |
| --- | --- |
| App | Xcode 16+, iOS 17+ device or simulator |
| Core library & tests | Swift 5.9+ on macOS **or Linux** |

```bash
git clone https://github.com/richardB520/liftnote_1.git
cd liftnote_1
swift test                     # core logic, runs on macOS and Linux
open LiftNote.xcodeproj        # the iOS app
```

The Xcode project is generated. After adding or removing a `.swift` file run:

```bash
python3 tools/gen_xcodeproj.py
```

## Code layout

- `LiftNote/Core` – Foundation-only domain logic (models, templates, weekly volume, voice parser). **Keep it free of UIKit/SwiftUI** so it stays testable on Linux.
- `LiftNote/App`, `LiftNote/Views` – SwiftUI app, persistence, speech, notifications.
- `LiftNoteWidgets` – Live Activity for the rest timer.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design rules (what counts as a working set, how templates are built, how the parser assigns weights to sets).

## Pull requests

1. Fork and create a branch from `main`.
2. Add or update tests for behaviour changes in `Core`.
3. Make sure `swift test` passes and the app builds (`CI` runs both).
4. Describe *what* and *why* in the PR; link the issue if there is one.
5. Add a line to `CHANGELOG.md` under **Unreleased**.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE) and that you will follow the [Code of Conduct](CODE_OF_CONDUCT.md).
