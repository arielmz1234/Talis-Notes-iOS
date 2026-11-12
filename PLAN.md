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
- [x] Quick colours and three sizes in the toolbar
- [ ] Line styles (dashes) for ink
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
- [x] Shape dots (every kind's `withHandle`, tests ported) and snapping (`Snap`, `SnapTest` ported); dots snap
- [x] Snapping when moving/drawing shapes; resize and move chips; rotate handle
- [x] Shapes Style tab (own colour/size/opacity/line/fill, Like the pen, snap and hold switches)
- [x] Soft selection after drawing with the Shapes tool
- [ ] Soft selection after hold-to-shape / pen tap on a shape; fill tool; subject packs
### 7. iPhone layout throughout (view-only by default, Write button)
### 8. App Store readiness (icon done from `tools/icon-source.png`; privacy manifest, screenshots, store text)
