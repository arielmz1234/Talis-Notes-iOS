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

Night of 10–11 Nov 2026 (same session, continuing):
- Seen in screenshots:
  - the toolbar and pen panel match Android on iPad, light and dark (run 42901014073);
  - the pen panel fits an iPhone (run 42906901522);
  - the ⋯ menu (`Notebook/MoreMenu.swift`), readable in dark mode once popovers got the app's
    surface colour (run 42913922426);
  - quick open beside Back (`Notebook/QuickOpen.swift`);
  - the new-notebook card on iPad (`Theme/PaperPicker.swift`, Android's paper picker with More);
  - library cards showing the first page with its writing (`Notebook/Thumbnail.swift`, saved as
    `thumbs/<id>.png` when a notebook closes).
- Built, not yet seen in a screenshot (run 42919352781 has them):
  - our own lasso (`Notebook/Selection.swift`): a dashed loop picks up whatever it touches
    (`Lasso.touchesPath`), a dashed frame, drag inside to move;
  - the selection menu (`Notebook/SelectionMenu.swift`): Copy, Cut, Duplicate, Box around, Delete;
  - hold 0.6 s on the page with something copied → Paste bubble;
  - the hint line;
  - the new-notebook card fitting an iPhone.
- Fixed: undo bringing back erased or deleted strokes stored them with the pen in use (wrong colour
  or type). The coordinator now keeps `archive` (every stroke seen, by key) and `pending` (strokes
  the app adds itself), and `sync` uses them.
- Ported into the ⋯ menu: Whole page, Paper, Dark paper, Draw with finger (Auto/On/Off → PencilKit
  drawingPolicy), Tap 2 fingers to undo and 3 to redo, Write between pages, Full screen, View only
  (tablets keep a `viewOnly` list, as Android's `AppSettings.viewOnly`).

Next (in this order):
- Check run 42919352781's screenshots: `4d-lasso` (selection frame and menu), iPhone new notebook.
- Selection menu's ⋯ (Colour, Thickness, to front/back, mirror, lock); the resize chip, the move
  chip and the rotate handle on the selection frame; the lasso panel (Lasso / Free form,
  Screenshot, Pick up locked items).
- Pages overview (⋯ menu › Pages), Endless canvas switch, Export PDF.
- Fill, laser, shapes (with hold-to-shape), picture/camera/PDF insert, voice memo, typed text; line
  styles (dashes); the highlighter's straight lines and square tip.
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
- The lasso pan is allowed to begin but never begins (run 42989992216; see Session 2's "Found").
- Shapes (from Android or hold-to-shape) can't be erased or lassoed yet.
- After a lasso move, the moved strokes are swapped for their stored form, so the lasso selection
  ends (PencilKit's lasso). Our own lasso will replace it.
- New strokes are kept as PencilKit drew them until reopened (control points ≈ samples); strokes
  loaded from Android go through PencilKit's spline, so they look slightly smoother than on Android.

## Session 2 (11 Nov 2026, scheduled run, owner's Windows PC)

Found on start: the night session's last commit (Export PDF, 11ba273) was never pushed, and its
notes stopped before its last three commits. Those commits, all built green in CI before Export:
- the selection menu's ⋯ (colour, thickness, to front/back, mirror) — 61cbdef;
- the lasso running alongside PencilKit's touch handling, simulators booted before tests — 314a6a1;
- the pages overview from the ⋯ menu (every page, go to, delete, add) — e9b3906;
- Export PDF from the ⋯ menu (Best / Balanced / Light with the real size, Save or Share) — 11ba273,
  pushed this session; it builds in the same run as hold-to-shape below.

Seen in run 42930179315's screenshots: the lasso still picks nothing up in the UI test (no loop,
frame or menu in `4d-lasso` on iPad or iPhone; a tiny mark appears in the iPad's bottom-right
corner). Not solved yet: see Known problems.

Done this session:
- `TaliCore/ShapeRecognizer.swift`: Android's `ShapeRecognizer.kt` ported line for line (lines
  snapping to 45°, arrows, arcs with the half-circle snap and hook trimming, curves, L/Z polylines,
  circles, ellipses, triangles incl. right-angle and isosceles snaps, rectangles/squares, diamonds,
  regular pentagons/hexagons, stars), plus `Geo.resample/simplify/meanDistToPolyline/centroid`.
  `ShapeRecognizerTests` ports all of `ShapeRecognizerTest.kt` (a seeded SplitMix generator
  replaces Kotlin's `Random(7)`, so the wobble differs; the thresholds are the same).
- Shapes are written the Android way: `ShapeGeometry.json` (kotlinx's form: "type" key, defaults
  left out), `ShapeRow.row(id:z:)` (kind 1, extra "fill"/"locked"/"line"), `bounds`, `transformed`.
  `.poly` gained `rotation` (Android stores it for rectangles).
- App: hold-to-shape (`Notebook/HoldToShape.swift`). A `StrokeWatcher` gesture recogniser watches
  the writing touch without ever recognising (PencilKit keeps the stroke). After 0.45 s resting
  (7 pt tolerance, stroke ≥ 24 pt on screen) the stroke is recognised; PencilKit's live stroke is
  cancelled by switching its drawing recogniser off and on (and `sync` drops it if it arrives anyway,
  `isSnappedStroke`); the live shape is drawn in a CAShapeLayer and follows the pen (a line's end
  snaps to 45°, others scale round their middle, 0.15–8×); on lift it's stored as a shape row,
  drawn by the page layer, one undo step (redo works too). Medium haptic on the snap.
- UI test: a sloping line held at its end, which should come out exactly level in `4-notebook`.

Decisions:
- Hold-to-shape is always on (Android's default); the switch lives in the Shapes panel's Style tab,
  which isn't ported yet.
- Shapes keep being drawn by the page layer under the writing. So shapes made here can't yet be
  erased or picked up with the lasso (PencilKit only knows ink). Needs our own item model for
  shapes in the eraser and lasso — next big step.
- Not done from Android's hold-to-shape: snapping a line's start/end to other shapes (`Snap`),
  custom and subject-pack shapes, the measuring badge, the square/circle diagonal hint.

Verified (run 42989992216, green):
- All 73 TaliCore tests pass, the ported `ShapeRecognizerTests` included. (The first run,
  42989607121, failed: Swift couldn't type-check a `max { }` closure in `fitCurve` in time; it's now
  plain loops.)
- Hold-to-shape in the app: in `ipad-he-4-notebook` the sloping line held at its end came out
  exactly level, drawn by the page layer. On the iPhone the same drag is ~7° off level (narrow
  screen), past the 6° snap, so it stays at its angle but is a clean shape (thin, straight).
- Only ipad-he and iPhone screenshots came out: the ipad-light run couldn't find its simulator, and
  ipad-dark timed out setting the orientation. CI flakiness; rerun before reading anything into it.

Found:
- A shape draws thinner than PencilKit's ink at the same pen size (PencilKit's monoline widens the
  width it's given). Android draws both with the same brush. Match them, e.g. scale PencilKit
  widths, or draw shapes with the factor PencilKit uses. Check against Android shots.
- Lasso: the test build now shows `gestureRecognizerShouldBegin` returning true for the lasso pan
  ("lasso should begin"), but the pan's `.began` never arrives ("lasso began" never shows). So
  another recogniser wins after it's allowed to start, probably one inside PKCanvasView. Try:
  `canvas.gestureRecognizers?.forEach { if $0 !== lasso.pan { $0.require(toFail:) … } }` for
  PencilKit's own ones while the lasso is on, or watch raw touches like `StrokeWatcher` does.

Next:
- Lasso UI test picking nothing up (see above).
- Eraser and lasso for shapes; the Shapes tool and panel; snapping.

### Session 2, continued (owner said keep going)

- Lasso fixed (run 42997378616, seen in `ipad-light-4d-lasso`): it now follows its own touches with a
  `StrokeWatcher` (like hold-to-shape) instead of a `UIPanGestureRecognizer`, which PKCanvasView let
  begin but never began. 191 loop points, both strokes picked, frame and menu showing. A second
  finger cancels the loop (pinch/scroll).
- The UI test now reopens the notebook (`5b-reopened`). It showed two bugs:
  1. **Reloaded ink is a hairline** (~1 px) while live ink was ~4.5 pt for a 2.5 pt fineliner. So
     `InkStroke.pkStroke` point sizes don't render like PencilKit's live tool width. The test build
     now shows "ink tool W point P max M n N" for each new stroke (hint in `4-notebook`) to
     measure the relation. Then make live and reloaded match Android's width.
  2. The lasso's own drag was stored as an invisible ink stroke (PencilKit kept drawing in the
     lasso's clear ink). Strokes arriving while the lasso is the tool are now dropped in `sync`.
     PencilKit drawing during the lasso should also be truly off (`drawingGestureRecognizer`
     disabled evidently isn't enough on iOS 26).
- Shapes in the lasso and eraser (`Notebook/ShapeSelection.swift`): the lasso picks up shapes it
  touches (unlocked); move (carried in an overlay layer, page tiles redrawn once), copy, cut,
  duplicate, paste, recolour (keeps the shape's alpha), thickness, mirror and delete include them,
  and undo restores shapes with the drawing (`record(_:shapes:)` → `setShapes`, which saves only
  what changed). The eraser takes whole shapes it passes over (its own watcher; one undo step for
  the shapes). Arrange (front/back) is ink only: shapes are always under the writing here.
- Shapes tool (`Notebook/ShapeTool.swift`, `ShapesPanel.swift`, `TaliCore/ShapeKinds.swift` with
  `ShapeKindTests`): seen in run 43004155595 — the panel (`4e-shapes-panel`: 16 standard tiles and the
  7 civil-engineering symbols, Rectangle chosen in blue) and an ellipse dragged out
  (`4f-shape-drawn`), the toolbar button showing the ellipse. The engineering symbols are in the
  panel under "Civil Engineering" (Android has them in the Civil subject of More shapes; the
  subject packs aren't ported). No Style tab yet: shapes take the last pen's colour and size.
- Same run, reopened (`5b-reopened`): the lasso's drag is no longer saved. Reloaded ink was still
  a hairline, probably because a finger's stroke stores pressure 0 and was reloaded with force
  0.01. Pens without pressure now reload at force 1 (`InkStroke.force`). The test build shows
  "live … | loaded …" numbers in `5b-reopened` to confirm.
- The lasso's menu stayed up after switching tools: `clearSelection` from inside `updateUIView`
  changed SwiftUI state mid-update. It's now deferred.
- PDF and picture import (`Data/Imports.swift`, the + is now a system menu: Notebook / File;
  `KindBadge` on cards). Seen in run 43011336605: the menu (`2b-add-menu`), and a seeded two-slide
  PDF opening just for looking with Write (`5c-pdf`). On a tablet a PDF/picture opens for looking
  until its first Write (`writeOn`, as Android). Found there: the slide wasn't fitted to the screen
  (zoom 100%), and the page chip said 1 / 1. Both came from state changed during the canvas's first
  update (`reportUndo`, first fit), now deferred. Not seen yet.
- Ink width, measured (`5b-reopened` hint): a monoline tool of width 2.4 gives live points 4.40
  wide (1.83×); reloaded strokes use 2.4 exactly (Android's width), hence "thin after reopening". Now
  the tool gets size ÷ factor (`InkWidth`, 1.83 for monoline at first, learned per ink from strokes
  without pressure), so live and reloaded match Android. Not seen yet. Pressure inks (fountain,
  pencil, calligraphy) keep factor 1 until measured.
- Not done for PDFs yet: sharp pages at zoom (`SharpPdf`), the Adding… pill, Photo and Camera in
  the + menu, Save-as-draft PDFs from other apps.
