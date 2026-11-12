# Plan: Tali's Notes for iPad and iPhone

The Android app (`C:\dev\Talis-Notes`, its `CLAUDE.md` and `README.md`) is the spec. See `BRIEF.md` for the brief.

## Structure

- `Packages/TaliCore`: logic with no screen (geometry, page layout, library model, SQLite with the
  Android schema, later the item codec, backup zip, shapes, snapping, lasso, recogniser). Tested
  with `swift test` (Swift Testing). Ported Android unit tests live here.
- `App/`: the SwiftUI app (`project.yml` → XcodeGen makes the Xcode project; never hand-edit it).
- `UITests/`: screenshot tests run by CI on iPad and iPhone, light, dark and Hebrew.
- Strings: `App/Resources/Localizable.xcstrings` is generated from the Android `strings.xml` files
  by `tools/import_strings.py` (keys = Android resource names). Re-run it after pulling Android.

## Milestones

### 1. Project, CI, theme
- [x] XcodeGen project, Swift package, CI on macOS (core tests, build, screenshots, unsigned .ipa)
- [x] Colours (lilac light/dark), fonts (Figtree, Bricolage, Heebo, Vazirmatn), cloud surface, sky clouds
- [x] String catalog from Android, six languages
- [x] Settings card (theme, Cloudy/Minimal style, language via iOS Settings)
- [x] Colour families (Sky, Sage, Peach)
- [ ] Gliding selection, cloud-puff "goes away" mist

### 2. Library
- [x] Sidebar (All, Starred, Recently deleted, folders tree), phone drawer
- [x] Search, sort (edited, opened, created, name; tap again to reverse), greeting
- [x] Notebook cards (paper preview, cover spine, star), folder cards, context menu (open, star, rename, move, duplicate, delete)
- [x] New-notebook card (name, paper, pages/endless, orientation, cover)
- [x] Recently deleted (restore, delete forever, empty, 30-day sweep); names kept apart per place
- [ ] Real page previews (thumbnails of the writing), PDF/picture sheet cards
- [ ] Picking several notebooks, folder colours/rename/move, + menu (File, Photo, Camera)

### 3. Notebook
- [x] A4 pages in a column with papers, zoom (first version, SwiftUI)
- [x] Canvas: PKCanvasView over a tiled page layer (paper, Android shapes and pictures), zoom, pages grow as you write
- [x] Ink: PencilKit live drawing, every stroke stored as an Android ink row (round trip tested)
- [x] Pens (fineliner, fountain, pencil, calligraphy, highlighter), type/colour/thickness panel
- [ ] Line styles (dashes) for ink, quick colours and three sizes in the toolbar
- [x] Eraser and lasso (PencilKit's own for now), undo/redo
- [x] Our own lasso and selection menu (with ⋯), page overview, Export PDF
- [ ] Precise eraser of our own; lasso UI test picking up
- [x] iPhone: opens view-only, Write button remembered per notebook
- [x] Toolbar, panels, top bar (quick open, undo/redo, eye, ⋯); phone toolbar with folded tools

### 4. Backups
- [x] Android ink format (`StrokeInputBatch.encode`: gzip'd protobuf) read/write; shape JSON read (drawing only)
- [x] Backup .zip read/write (`BackupArchive.kt`), merge restore, Backups card (save file / restore files)
- [ ] iCloud (per-notebook files, off in the free-signing build)
- [ ] Google Drive (same layout and appProperties as Android)

### 5. PDFs, pictures, text
- [x] + menu (Notebook, File, Camera, Photo); PDF and picture items with Android's naming and badges
- [x] PDF pages drawn as vectors (sharp at any zoom); open for looking until Write
- [x] Typed text: keyboard button, Android placement, tap to edit, A−/A+, lasso and eraser
- [ ] PDF export of imported PDFs at full quality; "Adding…" pill; drafts from other apps
### 6. Shapes, hold-to-shape, snapping, fill, the rest of CLAUDE.md
- [x] Hold-to-shape (recogniser ported with its tests; shapes stored the Android way)
- [x] Shapes in the eraser and lasso; Shapes tool and panel (standard + civil symbols)
- [ ] Shapes Style tab, shape dots and resize/rotate chips, snapping, fill, subject packs
### 7. iPhone layout throughout (view-only by default, Write button)
### 8. App Store readiness (icon done from `tools/icon-source.png`; privacy manifest, screenshots, store text)

## Parity with Android (goal set 11 Nov 2026: everything except backups, iCloud and Drive)

Worked in areas that touch different files, each by one agent in its own worktree with its own
simulators and its own UI test class (`UITests/<Area>Tests.swift` on `ShotCase`;
`ONLY=<Class> sh scripts/local-shots.sh …` runs one). Android item numbers are from its CLAUDE.md.

- [x] Shape editing: dots, resize/turn chips, move chip, triangle corners, part circle and arc ends,
      circle radius dot, soft selection, measuring badges (items 13, 14, 17, 18, 23, 24, 58, 85).
      Merged 12 Nov. Left: snapping and joint dots (with Selecting, more); rotation snaps to 45° as
      Android's code does (its README says 15°); stale ink after a lasso resize seen once on iPhone.
- [x] Pens and ink: line styles (19), quick colours and toolbar colours per pen (20, 30, 37),
      highlighter straight lines and square tip (25), laser (26), eraser filters and a precise
      eraser of our own, Apple Pencil double-tap and squeeze (Android's side button). Merged 12 Nov.
      Not checked without a real Pencil: double-tap and squeeze, palm next to the pencil. Left: dashes
      follow the curve (Android lays straight pieces); the eraser takes text boxes (Android's doesn't);
      the gliding colour ring; on the iPad Pro 13 only, picking the highlighter right after removing
      a pen with its panel open closes the panel instead.
- [x] Library: folder colours, rename and move, folders inside folders with tiles and a path (3),
      the + card (63), mist when things go (8), gliding highlight everywhere (7), first-run tour (61),
      Select several notebooks. Merged 12 Nov. Left: the tour has 4 of 8 steps and Settings has no
      Tips card (both wait for notebook features); hold menus are iOS context menus.
- [x] Media: voice memos (44, 45), the camera with crop and looks (64, 81), PDFs and pictures from
      other apps and drag and drop (52), Export PDF's layouts (one long page, the PDF's own pages),
      the "Adding…" pill, pictures into a notebook, crop pictures (81). Merged 11 Nov; MediaTests pass
      on iPad. Not on a simulator: live camera, real microphone, a real drag or Open in. Left: crop
      only right after adding (needs pictures in the lasso), no share extension, writing exports as a
      picture (PencilKit), memos don't follow page delete/reorder.
- [x] Pages and paper: pull to add a page (1, 32), Endless canvas switch and page guides, your own
      paper with opacity (2, 9), line thickness (21), page numbers, hide the toolbars with mist (5),
      the pages overview (move, pick several). Merged 12 Nov. Left: the new-notebook card doesn't offer
      her papers; dragging a picked group of pages; the overview's Duplicate to check by hand (XCUITest
      taps Delete instead on the iPad Pro 13, likely the simulator).
- [x] Shapes, more: the Style tab, fill (16), subject packs and joints (53, 55, 56), my shapes ($P
      matcher), one rectangle tool with the square snap (38). Merged 12 Nov. Left: snapping (49),
      fills following the lasso and eraser, joint dots (with shape editing), Save as shape on a phone
      (the selection menu runs off the edge).
- [x] Selecting, more: lock and Unlock all (27), free form (36), screenshot lasso, the folding menu
      that scrolls on a phone (42), pictures and fills in the lasso, typed text picked up, resized,
      recoloured (46), snapping (49) and joint dots. Merged 12 Nov with pens unified (one eraser,
      one undo step, one Picks up).
- [ ] Phone layout pass over all of the above (67, 73)

### Parity leftovers (12 Nov, from the agents' reports)
A. Notebook and phone:
- [ ] Phone: the tools row (eight tools) puts the eraser off the left edge; a pass over every phone
      screen (toolbar, panels, menus, cards) for anything cut off or covered.
- [ ] Typed text's small bar (size, colour, delete, done) as Android's TextEditor.
- [ ] The eraser leaves typed text alone (Android's `eraserHits` is false without a pen).
- [ ] After a precise erase cuts a fill's outline, the pieces still travel with the fill (Android's
      `finishErase` regroups `walls`).
- [ ] Memos follow page delete and reorder; the overview drags a picked group of pages; a deleted
      page goes on a puff.
- [ ] Carrying a selection or memo to a screen edge scrolls the page (Android's `edgeStep`).
- [ ] iPad Pro 13: the first tap on another pen after "Remove this pen" only closes the panel.
- [ ] The 14 remaining rounded `contentShape`s (taps reach the neighbouring control).
B. Library, look and export:
- [x] The first-run tour's other steps (subject shapes, voice memos and PDFs, Apple Pencil tricks)
      and Settings' Tips and tricks card.
- [x] The new-notebook card and library card pictures show her own papers.
- [x] Export PDF draws writing as vector lines (Android's), not a picture.
- [x] The Shapes tool's tips ("Drag on the page to draw the shape", part circle).
