# Progress

## How to pick this up

1. Read `BRIEF.md`, `PLAN.md`, this file, `OWNER_TODO.md`.
2. `gh run list -L 3` (GitHub CLI at `C:\Program Files\GitHub CLI\gh.exe`), then look at the last run's
   screenshots: `gh run download <id> -n screenshots -D <scratch dir>`. Landscape iPad screenshots
   come out sideways (rotate them when reviewing; the test's attempt to upright them may not work).
3. There is no Swift on the Windows PC; every compile happens in CI (about 15–20 minutes with
   screenshots, macOS runners sometimes queue). Batch changes, and read compile errors with
   `gh run view <id> --log-failed | grep error:`.

## Session 1 (10 Nov 2026, the owner's Windows PC)

Environment: Windows, no Swift or Xcode locally, Docker not running. CI on GitHub Actions
(`macos-15`, Xcode 16.4). The repo is public, so its macOS minutes are free.

Done:
- Repository set up: BRIEF, PLAN, OWNER_TODO, XcodeGen `project.yml`, `Packages/TaliCore`, CI
  (core tests, build, screenshots on iPad light/dark/Hebrew and iPhone light/dark, unsigned .ipa).
- TaliCore (pure Swift, tested):
  - `Pt`, `Rect`, `Affine` (Android's field names and `then` order), `Geo`, `Pages`
    (A4 layout, clip rules, page reorder helpers).
  - The library model: `NotebookMeta`, `Folder`, `DocKind`, `PaperStyle`, covers, sort,
    natural order, numbered names, greeting.
  - `NotesDb`: SQLite3 with the Android schema VERSION 8 and its upgrade steps.
  - `InkCodec`: androidx.ink's stroke storage (gzip'd protobuf, delta-coded runs), worked out
    from a real Android stroke (fixture in the tests) and written the same way.
  - `Gzip`, `CRC32`, `Deflate` (Apple's Compression), and `Zip` reader/writer.
  - `BackupArchive`: write/restore the Android backup .zip, with merge (newer wins, nothing
    deleted, older schemas, names kept apart).
  - `Lasso` geometry.
  - Ported tests: MovePageTest, FreeNameTest, LassoTest, FreeSelectTest, plus page layout,
    database, ink, zip and backup round trips.
- App:
  - Theme: lilac light/dark, variable fonts (Figtree, Bricolage, Heebo, Vazirmatn with weight
    axes), the cloud surface (bumps ported exactly), sky clouds, papers (all eight built-in ones).
  - Library: sidebar, phone drawer, search, sort, cards, folders, Recently deleted, context menu,
    new-notebook card, Backups card (save a backup file, restore files).
  - Notebook: `NoteCanvas` is a PKCanvasView. PencilKit draws the live stroke; each finished stroke
    is stored as an Android ink row. Strokes that run off their page are hidden past it with
    PencilKit's stroke mask. Pages are drawn by a CATiledLayer underneath. Writing on the last page
    adds a page. Pens (fineliner, fountain, pencil, calligraphy, highlighter) with a panel for type,
    colour and thickness; PencilKit's eraser and lasso; undo and redo.
- Strings: 827 keys in six languages generated from Android.
- App icon from `tools/icon-source.png`.

Verified by looking at CI screenshots:
- Run 42853258304: the library on iPad (landscape, portrait, dark, Hebrew mirrored with the
  sidebar on the right) and iPhone (light, dark).
- Run 42863082146 (all green, core tests included):
  - Fonts load: Figtree for text, Bricolage for headings, Heebo in Hebrew.
  - Paper previews show their lines.
  - The new-notebook card fits iPad and iPhone.
  - Backups and Settings cards look right.
  - Writing works: two finger strokes drawn in the UI test show on the page in a new notebook,
    on iPad and iPhone.
  - The notebook keeps the English layout in Hebrew.
- Found in that run and fixed in the next commit (run 42870297252):
  - Dark mode lightened black ink on the white page (PencilKit adapts ink to the interface style).
  - The bars should be the mist colours.
  - The page started under the toolbar.
  - Also added in that commit: iPhone view-only with Write.

Not verified yet: anything about real Apple Pencil feel (pressure, latency) — needs a device.
Restoring a real Android backup on iOS is covered by unit tests (ink fixture, schema 7 database),
not yet by opening one in the app.

- Run 42883014643 (green): the library and notebook bars redone to match the Android app's
  current screenshots (`C:\dev\Talis-Notes	ools\emulator\shots\lib.png`, `nb.png`, 9 Nov 2026):
  - one continuous sky behind the sidebar and the main area;
  - the wordmark with its highlighter swipe;
  - the 52 pt heading with a count and date line;
  - plain white search and sort boxes (no cloud), the + as a 48 pt gradient square;
  - the ruler, the RECENT label, and landscape cards (1.32) with a stitched spine;
  - in the notebook: back on a three-puff cloud, undo and redo, the name pill with a pencil, the eye.
  Checked in screenshots: iPad light, dark, portrait, iPhone.
- Dialog cards (new notebook, backups, settings) lost their cloud bumps to match Android's
  `DialogCard` (radius 24, shadow 12). Pushed at the end of session 1, not yet seen in a screenshot.

**Owner's rule (10 Nov 2026): the app must look exactly like Android.** Before any design
decision, read the Android composable and look at its screenshots in
`C:\dev\Talis-Notes	ools\emulator\shots` (newest first: `ls -t`). Copy crowns (`CloudCrown`), radii,
sizes and type styles (`TaliType` mirrors Android's Material names) rather than guessing.

Next (in this order):
- Settings card like Android's `settings.png`: Language row, Colours tiles, Theme and Style side
  by side, PDFs from other apps, Take the tour, Done at the bottom right; section labels in caps.
- New-notebook card: compare with Android's `NewNotebookDialog` (`ui/library/Dialogs.kt`).
- The main toolbar like `nb.png`: pens drawn like Android's `PenGlyph`, a chevron, the quick
  colours and three sizes, then eraser, lasso, fill, laser, shapes, picture, mic, keyboard (the ones
  not ported yet should wait rather than show dead buttons). Page and zoom chips at the bottom right.
- Real page thumbnails on cards (render the first page with its strokes).
- Our own lasso and selection menu, the ⋯ menu, quick open, Select (picking several notebooks).
- Shapes and pictures from Android show under the writing; typed text and "param" designs don't yet.
- iCloud (switched off in the free-signing build), then Google Drive.

Decisions:
- The bundle id is `com.tali.notes`, the same as Android (Apple's ids are separate).
- Swift Testing (`import Testing`) for TaliCore tests.
- Ink: PencilKit for live drawing and display (Apple Pencil latency, zoom, tiling for free), with
  the Android ink format as the stored truth. A PKStroke's control points are stored as the
  Android inputs. Pressure = force / 2; tilt = π/2 − altitude; orientation = azimuth.
  Dashed line styles will need our own rendering later (PencilKit has no dashes).
- World units = points at zoom 1 (Android's dp).

Known problems:
- After a lasso move, the moved strokes are swapped for their stored form, so the lasso selection
  ends (PencilKit's lasso). Our own lasso will replace it.
- New strokes are kept as PencilKit drew them until reopened (control points ≈ samples); strokes
  loaded from Android go through PencilKit's spline, so they look slightly smoother than on Android.
