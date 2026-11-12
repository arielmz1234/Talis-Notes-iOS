import PencilKit
import TaliCore
import UIKit

/// Anything on the page that can be picked up (Android's `CanvasItem`): writing, a shape, typed
/// text, or a picture (an area fill is a picture too). A whole PDF page is never one.
enum PageItem {
  case ink(InkStroke)
  case shape(ShapeRow)
  case text(TextRow)
  case picture(PictureRow)

  var id: String {
    switch self {
    case .ink(let s): s.id
    case .shape(let s): s.id
    case .text(let t): t.id
    case .picture(let p): p.id
    }
  }

  var z: Int64 {
    switch self {
    case .ink(let s): s.z
    case .shape(let s): s.z
    case .text(let t): t.z
    case .picture(let p): p.z
    }
  }

  var locked: Bool {
    switch self {
    case .ink(let s): s.locked
    case .shape(let s): s.locked
    case .text(let t): t.locked
    case .picture(let p): p.locked
    }
  }

  var bounds: TaliCore.Rect {
    switch self {
    case .ink(let s): s.bounds
    case .shape(let s): s.geometry.bounds(s.size) ?? TaliCore.Rect(0, 0, 0, 0)
    case .text(let t): TaliCore.Rect(TextLook.frame(t))
    case .picture(let p): p.rect
    }
  }

  /// The pen it was made with; pictures and text have none (the lasso's Images choice covers them).
  var pen: PenType? {
    switch self {
    case .ink(let s): s.pen
    case .shape(let s): PenType(rawValue: s.pen) ?? .FINELINER
    case .text, .picture: nil
    }
  }

  var picture: PictureRow? {
    if case .picture(let p) = self { return p }
    return nil
  }

  var shape: ShapeRow? {
    if case .shape(let s) = self { return s }
    return nil
  }

  var isFill: Bool { picture?.isFill ?? false }

  func withLocked(_ on: Bool) -> PageItem {
    switch self {
    case .ink(var s):
      s.locked = on
      return .ink(s)
    case .shape(var s):
      s.locked = on
      return .shape(s)
    case .text(var t):
      t.locked = on
      return .text(t)
    case .picture(var p):
      p.locked = on
      return .picture(p)
    }
  }

  func withZ(_ z: Int64) -> PageItem {
    switch self {
    case .ink(var s):
      s.z = z
      return .ink(s)
    case .shape(var s):
      s.z = z
      return .shape(s)
    case .text(var t):
      t.z = z
      return .text(t)
    case .picture(var p):
      p.z = z
      return .picture(p)
    }
  }

  /// Moved, resized, turned or mirrored by [m]. Writing, shapes and text come out unlocked; a
  /// picture keeps its lock (as Android's `transformed` does for each).
  func transformed(_ m: Affine) -> PageItem {
    switch self {
    case .ink(let s): .ink(s.transformed(m))
    case .shape(let s): .shape(s.transformed(m))
    case .text(let t): .text(t.transformed(m))
    case .picture(let p): .picture(p.transformed(m))
    }
  }

  /// What it offers for snapping (Android's `featuresOf`): shapes, pictures and text; not writing,
  /// a PDF's page or an area fill.
  var snapFeatures: SnapFeatures? {
    switch self {
    case .ink: nil
    case .shape(let s): s.geometry.snapFeatures()
    case .text: .ofBox(bounds)
    case .picture(let p): p.pdfPage || p.isFill ? nil : .ofBox(p.rect)
    }
  }
}

extension InkStroke: Equatable {
  static func == (a: InkStroke, b: InkStroke) -> Bool {
    a.id == b.id && a.z == b.z && a.pen == b.pen && a.tags == b.tags && a.color == b.color && a.size == b.size && a.inputs == b.inputs
  }

  /// Locked in place (the "LOCKED" tag in the pen column, as Android stores it).
  var locked: Bool {
    get { InkTags.isLocked(tags) }
    set { tags = InkTags.with(tags, locked: newValue) }
  }

  /// Its samples carried by [m], its thickness scaled with it; it comes out unlocked (Android's
  /// `InkItem.transformed` and `StrokeFactory.transform`).
  func transformed(_ m: Affine) -> InkStroke {
    var s = self
    s.inputs.points = inputs.points.map { p in
      var q = p
      let at = m.apply(Pt(p.x, p.y))
      q.x = at.x
      q.y = at.y
      return q
    }
    let k = m.scaleFactor
    if k != 1 { s.size = min(max(size * k, 0.3), 400) }
    s.locked = false
    return s
  }
}

extension FillPicture {
  var picture: PictureRow { PictureRow(row.row) ?? PictureRow(id: row.id, z: row.row.z, file: row.file, rect: row.rect) }

  /// The same coloured cells shown as [p] says (moved, mirrored, locked, outlining other lines).
  func with(_ p: PictureRow) -> FillPicture {
    guard let moved = FillRow(p.itemRow) else { return self }
    return FillPicture(row: moved, image: image, covered: covered)
  }

  init(row: FillRow, image: CGImage, covered: [Bool]) {
    self.row = row
    self.image = image
    self.covered = covered
  }
}

/// What's copied or cut, carried across notebooks (Android's `Clipboard`), in world units.
@MainActor
enum Clipboard {
  static var items: [PageItem] = []
}

/// Everything on the page but a PDF's own pages, as it stands: what one undo step puts back.
struct PageState {
  var drawing: PKDrawing
  var stored: [(key: NoteCanvas.Coordinator.StrokeKey, stroke: InkStroke)]
  var shapes: [ShapeRow]
  var texts: [TextRow]
  var pictures: [PictureRow]
  var fills: [FillPicture]
  var lockedInk: [InkStroke]
}

extension NoteCanvas.Coordinator {
  /// The pictures on the page (not a PDF's pages, which the page layer draws from the PDF, nor fills).
  var pictures: [PictureRow] { pages?.pages.under.pictures.map(\.row) ?? [] }

  /// Locked writing: kept out of PencilKit's drawing, so neither the pen nor the eraser touches it; the page draws it.
  var lockedInk: [InkStroke] { pages?.pages.under.lockedInk ?? [] }

  /// Everything that can be picked up, as it is on the page now (while something is being carried, as it was before).
  var pageItems: [PageItem] {
    let under = lasso.lifted ?? pages?.pages.under ?? UnderItems()
    return stored.map { .ink($0.stroke) } + under.lockedInk.map(PageItem.ink) + under.shapes.map(PageItem.shape) + under.texts.map(PageItem.text)
      + under.pictures.map { .picture($0.row) } + under.fills.map { .picture($0.picture) }
  }

  var pickedItems: [PageItem] { pageItems.filter { lasso.picked.contains($0.id) } }

  var pageState: PageState {
    let under = lasso.lifted ?? pages?.pages.under ?? UnderItems()
    return PageState(
      drawing: canvas?.drawing ?? PKDrawing(), stored: stored, shapes: under.shapes, texts: under.texts, pictures: under.pictures.map(\.row), fills: under.fills,
      lockedInk: under.lockedInk)
  }

  var topZ: Int64 {
    let under = pages?.pages.under ?? UnderItems()
    let all = [stored.map(\.stroke.z).max(), under.lockedInk.map(\.z).max(), under.shapes.map(\.z).max(), under.texts.map(\.z).max(), under.pictures.map(\.row.z).max(), under.fills.map(\.row.row.z).max(), shapeZ]
    return all.compactMap { $0 }.max() ?? 0
  }

  // MARK: One undo step for any change

  /// Makes this change one undo step: going back puts the page as it was in [before].
  func record(_ before: PageState) {
    canvas?.undoManager?.registerUndo(withTarget: self) { coord in
      MainActor.assumeIsolated {
        coord.finishText()
        let now = coord.pageState
        coord.clearSelection()
        coord.record(now)
        coord.restore(before)
        coord.reportUndo()
      }
    }
  }

  func restore(_ state: PageState) {
    guard let canvas else { return }
    setInk(state.stored, drawing: state.drawing, on: canvas)
    setShapes(state.shapes)
    setTexts(state.texts)
    setPictures(state.pictures)
    setFills(state.fills)
    setLockedInk(state.lockedInk)
  }

  /// Takes [old] off the page and puts [new] on it (an item in both is replaced where it is), as one
  /// undo step (Android's `commit(Change(old, new))`).
  func commit(remove old: [PageItem], add new: [PageItem]) {
    if old.isEmpty && new.isEmpty { return }
    endThicknessPreview()
    let before = pageState
    apply(remove: old, add: new)
    record(before)
    reportUndo()
  }

  func apply(remove old: [PageItem], add new: [PageItem]) {
    guard let canvas else { return }
    let gone = Set(old.map(\.id))
    var ink: [InkStroke] = [], locked: [InkStroke] = [], newShapes: [ShapeRow] = [], newTexts: [TextRow] = [], newPictures: [PictureRow] = [], newFills: [PictureRow] = []
    for item in new {
      switch item {
      case .ink(let s): if s.locked { locked.append(s) } else { ink.append(s) }
      case .shape(let s): newShapes.append(s)
      case .text(let t): newTexts.append(t)
      case .picture(let p): if p.isFill { newFills.append(p) } else { newPictures.append(p) }
      }
    }
    func merged<T>(_ now: [T], _ added: [T], id: (T) -> String) -> [T] {
      var waiting = Dictionary(added.map { (id($0), $0) }, uniquingKeysWith: { _, b in b })
      var out: [T] = []
      for item in now {
        if let replacement = waiting.removeValue(forKey: id(item)) { out.append(replacement) } else if !gone.contains(id(item)) { out.append(item) }
      }
      return out + added.filter { waiting[id($0)] != nil }
    }
    // Writing: PencilKit's drawing and what's stored of it change together, in stacking order.
    let strokes = canvas.drawing.strokes
    let live = stored.enumerated().compactMap { i, entry in i < strokes.count ? (pk: strokes[i], key: entry.key, stroke: entry.stroke) : nil }
    let fresh = ink.map { s -> (pk: PKStroke, key: StrokeKey, stroke: InkStroke) in
      let pk = s.pkStroke(mask: mask(for: s))
      return (pk, StrokeKey(pk), s)
    }
    if !fresh.isEmpty || live.contains(where: { gone.contains($0.stroke.id) }) {
      let stacked = merged(live, fresh, id: { $0.stroke.id }).enumerated().sorted { a, b in a.element.stroke.z != b.element.stroke.z ? a.element.stroke.z < b.element.stroke.z : a.offset < b.offset }.map(\.element)
      let next = Self.highlighterFirst(stacked) { $0.stroke }
      setInk(next.map { ($0.key, $0.stroke) }, drawing: PKDrawing(strokes: next.map(\.pk)), on: canvas)
    }
    setLockedInk(merged(lockedInk, locked, id: { $0.id }))
    setShapes(merged(shapes, newShapes, id: { $0.id }))
    setTexts(merged(texts, newTexts, id: { $0.id }))
    setPictures(merged(pictures, newPictures, id: { $0.id }))
    var byId: [String: FillPicture] = [:]
    for f in fills { byId[f.row.id] = f }
    // A copied fill shows the picture of the one it was copied from.
    let fillRows = merged(fills.map(\.picture), newFills, id: { $0.id })
    setFills(fillRows.compactMap { p in (byId[p.id] ?? fills.first { $0.row.file == p.file })?.with(p) ?? FillPicture(p.itemRow) })
    if let box = new.map(\.bounds).reduce(nil, { (all: TaliCore.Rect?, r) in all?.union(r) ?? r }) { growPages(toHold: box) }
  }

  private func setInk(_ next: [(key: StrokeKey, stroke: InkStroke)], drawing: PKDrawing, on canvas: PKCanvasView) {
    var was: [String: InkStroke] = [:]
    for (_, s) in stored { was[s.id] = s }
    let kept = Set(next.map(\.stroke.id))
    do {
      for id in was.keys where !kept.contains(id) { try parent.db.removeItem(id) }
      for (_, s) in next where was[s.id] != s { try parent.db.put(s.row, in: parent.notebook.id) }
    } catch {
      CrashNote.log("saving strokes: \(error)")
    }
    // Every stroke seen, so one brought back by PencilKit's own undo is stored exactly as it was.
    for (k, st) in stored { archive[k] = st }
    stored = next
    loading = true
    canvas.drawing = drawing
    loading = false
    touch()
  }

  func setPictures(_ new: [PictureRow]) {
    guard let pages else { return }
    let old = pages.pages.under.pictures
    if old.map(\.row) == new { return }
    var before: [String: PlacedPicture] = [:]
    for p in old { before[p.row.id] = p }
    let keep = Set(new.map(\.id))
    do {
      for p in old where !keep.contains(p.row.id) { try parent.db.removeItem(p.row.id) }
      for p in new where before[p.id]?.row != p { try parent.db.put(p.itemRow, in: parent.notebook.id) }
    } catch {
      CrashNote.log("saving pictures: \(error)")
    }
    // The same file shown the same way keeps the picture already decoded.
    func image(for p: PictureRow) -> CGImage? {
      (before[p.id] ?? old.first { $0.row.file == p.file }).flatMap { $0.row.file == p.file && $0.row.crop == p.crop ? $0.image : nil }
    }
    let placedNow = new.compactMap { p in image(for: p).map { PlacedPicture(row: p, image: $0) } ?? placed(p) }
    pages.pages.under.pictures = placedNow
    let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var area: CGRect?
    for p in old.map(\.row).filter({ after[$0.id] != $0 }) + new.filter({ before[$0.id]?.row != $0 }) { area = joined(area, CGRect(p.rect)) }
    redrawPage(area)
    touch()
  }

  func setLockedInk(_ new: [InkStroke]) {
    guard let pages else { return }
    let old = pages.pages.under.lockedInk
    if old == new { return }
    var before: [String: InkStroke] = [:]
    for s in old { before[s.id] = s }
    let keep = Set(new.map(\.id))
    // A stroke that only moved between PencilKit's drawing and here is still on the page: not removed.
    let live = Set(stored.map(\.stroke.id))
    do {
      for s in old where !keep.contains(s.id) && !live.contains(s.id) { try parent.db.removeItem(s.id) }
      for s in new where before[s.id] != s { try parent.db.put(s.row, in: parent.notebook.id) }
    } catch {
      CrashNote.log("saving locked writing: \(error)")
    }
    pages.pages.under.setLockedInk(new) { self.mask(for: $0) }
    let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    redrawPage(unionOf(old.filter { after[$0.id] != $0 } + new.filter { before[$0.id] != $0 }))
    touch()
  }

  /// Something new reaches below the last page: pages are added to hold it (they "keep coming as you write").
  func growPages(toHold box: TaliCore.Rect) {
    guard paged else { return }
    let need = layout.needed(box)
    if need > pageCount {
      pageCount = need
      updateContent()
      persistPages()
    }
  }
}
