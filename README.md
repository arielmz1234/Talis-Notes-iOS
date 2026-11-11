# Tali's Notes for iPad and iPhone

The Apple version of [Tali's Notes](https://github.com/arielmz1234/Talis-Notes), a handwriting notes app.
Work in progress: see `PLAN.md` and `PROGRESS.md`.

- `project.yml`: run `xcodegen generate` to make `TalisNotes.xcodeproj` (not in git).
- `Packages/TaliCore`: the logic without a screen; `swift test --package-path Packages/TaliCore`.
- `App/`: SwiftUI app. `UITests/`: screenshot tests.
- `tools/import_strings.py`: the string catalog from the Android app's strings.
- `tools/make_icon.py`: the app icon from the Android app's `tools/icon-source.png`.
- `scripts/local-shots.sh`: the screenshot test on a local simulator (see PROGRESS.md).
- CI (`.github/workflows/ci.yml`) builds, tests, saves screenshots and an unsigned `.ipa`.
