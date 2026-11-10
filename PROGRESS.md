# Progress

## Session 1 (10 Nov 2026, the owner's Windows PC)

Environment: Windows, no Swift or Xcode locally, Docker not running. Everything is built and
checked on GitHub Actions (macOS runner). The repo is public, so its macOS minutes are free.

Done:
- Repository set up: BRIEF, PLAN, OWNER_TODO, XcodeGen `project.yml`, `Packages/TaliCore`, CI.
- TaliCore: `Pt`, `Rect`, `Affine` (Android's field names and `then` order), `Geo`, `Pages`
  (A4 layout, clip rules, page reorder helpers), library model (`NotebookMeta`, `Folder`,
  `DocKind`, `PaperStyle`, covers, sort, natural order, numbered names, greeting), `NotesDb`
  (SQLite3, Android schema VERSION 8 with its upgrade steps). Tests ported from MovePageTest,
  FreeNameTest, plus page layout and database round trips.
- App: theme (lilac light/dark, fonts), cloud surface (bumps ported exactly), sky clouds, papers
  (all eight built-in papers drawn like `PaperRenderer`), library (sidebar, phone drawer, search,
  sort, cards, folders, Recently deleted, context menu), new-notebook card, a first notebook
  screen (pages with paper, pinch zoom, back).
- Strings: 827 keys in six languages generated from Android.
- App icon from `tools/icon-source.png`.

Verified: see the CI section below.

Next:
- Look at the first screenshots and fix the look.
- Milestone 3: the UIKit canvas and Apple Pencil ink (store strokes in Android's format so backups work).

Known problems / decisions:
- Decision: the bundle id is `com.tali.notes`, the same as Android (Apple's ids are separate).
- Decision: Swift Testing (`import Testing`) for TaliCore tests.
