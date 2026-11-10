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
  current screenshots (`C:/dev/Talis-Notes/tools/emulator/shots\lib.png`, `nb.png`, 9 Nov 2026):
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
`C:/dev/Talis-Notes/tools/emulator/shots` (newest first: `ls -t`). Copy crowns (`CloudCrown`), radii,
sizes and type styles (`TaliType` mirrors Android's Material names) rather than guessing.

Later in session 1 (owner's requests, 10 Nov 2026 evening):
- CI moved to `macos-26` (Xcode 26.6, iOS 26 simulators) for Liquid Glass. Screenshot runs take
  about 25–35 minutes there.
- The owner allows iOS-only touches that are clearly better (BRIEF.md, "Look"); behaviour and logic
  stay exactly as on Android. Apple design rules: `docs/apple-design-SKILL.md`.
- Done and seen in screenshots (run 42891226523):
  - glass thickness slider (`Theme/StepSlider.swift`, native Slider plus glass − / + on iOS 26);
  - Settings laid out like Android (Language row, colour tiles, Theme | Style segmented);
  - Android's `Segmented` with the gliding white pill (`Theme/Segmented.swift`).
- Done, build green, not yet seen in screenshots:
  - sky clouds burst into mist when tapped and re-form after 4 s (`Theme/CloudPuff.swift` ports
    `CloudPuff.kt`: same wisp grid, timing, easing);
  - cards shown over a dimmed screen (`Theme/DialogOverlay.swift`) instead of sheets (iOS 26 drew a
    panel behind them);
  - Select mode in the library (PickBar);
  - tap the notebook's name to rename it;
  - the main toolbar like Android's (`Notebook/Toolbar.swift`): `PenGlyph` ported exactly, pens
    standing in a tray with the active one lifted, the arrow to pen settings, toolbar colours,
    `QuickSizes`, eraser and lasso with the blue gliding highlight;
  - `PenPanel` (types, sample stroke, three sizes, Size slider, colours, how many in the toolbar);
  - `EraserPanel` (whole strokes / precise, size);
  - page and zoom chips (go to page, tap zoom to fit).

Next (in this order):
- Check the screenshots of the toolbar, panels, dialogs and Select mode (light, dark, iPhone).
- Notebook, still missing compared with Android (`C:/dev/Talis-Notes/tools/emulator/shots/nb.png`):
  - the ⋯ menu (paper, dark paper, pages overview, endless/pages, export PDF);
  - quick open (recent notebooks), the lasso panel and our own selection menu
    (copy, cut, duplicate, delete, colour, thickness…);
  - fill, laser, shapes (with hold-to-shape), picture/camera/PDF insert, voice memo, typed text;
  - two-finger undo / three-finger redo; line styles (dashes);
  - the highlighter's straight lines and square tip.
  Port each from its Android code with its behaviour.
- New-notebook card: compare with Android's `NewNotebookDialog` (`ui/library/Dialogs.kt`).
- Real page thumbnails on cards (render the first page with its strokes).
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
