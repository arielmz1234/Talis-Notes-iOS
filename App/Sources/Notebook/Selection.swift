import PencilKit
import TaliCore
import UIKit

/// What's picked up (by the lasso's loop, a tap, or a shape just drawn) and what the touch on it is doing.
@MainActor
struct LassoState {
  /// The touches that draw the lasso's loop or take hold of the selection (a watcher like
  /// hold-to-shape's: a pan recogniser was allowed to begin on PKCanvasView but never began).
  var pan: StrokeWatcher?
  var hold: UILongPressGestureRecognizer?
  /// The loop being drawn, in world units.
  var loop: [Pt] = []
  /// Everything picked up, by id (writing, shapes, text, pictures and fills alike), and its bounds.
  var picked: Set<String> = []
  var bounds: CGRect?
  /// The page's items as they were before what's picked up was lifted off it to be carried.
  var lifted: UnderItems?
  let shapeLayer = CALayer()
  /// The touch moving, resizing, turning or reshaping what's picked up, how far it has taken it, and
  /// the drawing before it began.
  var drag: SelectionDrag?
  var transform = Affine.identity
  var before: PKDrawing?
  /// The shape picked itself up when it was drawn: the pen still writes inside it (Android's `softSelection`).
  var soft = false
  /// The menu steps aside after an edit and comes back by itself; a newer ticket calls that off.
  var menuClosed = false
  var menuTicket = 0
  /// Ink and arcs have no direction of their own: how far each was turned, so the next turn's badge carries on.
  var turnedBy: [String: Float] = [:]
  var claim: (touch: ObjectIdentifier, began: TimeInterval, grab: SelectionGrab?)?
  /// PencilKit strokes begun after this belong to a touch that was editing the selection: dropped.
  var editSince: Date?
  var chipsBackAt: Date?
  /// A newer ticket calls off taking the carried items' overlay away (see `dropShapes`).
  var overlayTicket = 0
  /// Where a hold offered Paste (world units).
  var pasteAt: CGPoint?
  /// Where the lasso's touch last was (world units).
  var lastAt: CGPoint = .zero
  let loopLayer = CAShapeLayer()
  let chrome = SelectionChromeView()
  /// What this drag snaps to and the guides it shows (see Snapping.swift).
  var snap = SnapState()
  /// The padlock shown as things lock and unlock, and the finger held on a locked item (see Lock.swift).
  var lock = LockState()
  /// The screenshot lasso's flash, and the pictures it has taken (see ScreenshotLasso.swift).
  var shot = ShotState()
}

/// The lasso and the selection menu's actions (Android's `NoteCanvasView` lasso, `finishLasso`,
/// `withFills`, the selection menu and hold-to-paste): a dashed loop picks up whatever it touches,
/// free form whatever the pen passes over, a dashed frame shows it, and the menu copies, cuts,
/// duplicates, boxes, deletes, recolours, mirrors, arranges and locks it. Moving, resizing and
/// turning it are in SelectionEdit.swift. Holding still on the page with something copied offers
/// Paste there.
extension NoteCanvas.Coordinator: UIGestureRecognizerDelegate {
  static let pasteHold: TimeInterval = 0.6
  static let duplicateOffset: Float = 24
  static let frameGap: Float = 12

  func installSelection(on v: PKCanvasView) {
    let pan = StrokeWatcher(target: nil, action: nil)
    pan.delegate = self
    pan.accepts = { [weak self] t in self?.takes(t) ?? false }
    pan.began = { [weak self] t, _ in self?.lassoStep(.began, t) }
    pan.moved = { [weak self] t, e in
      // The loop takes every sample; a drag only where the touch is now (redrawing what's carried
      // for each sample would fall behind the pen).
      let samples = self?.lasso.drag == nil ? e.coalescedTouches(for: t) ?? [t] : [t]
      for s in samples { self?.lassoStep(.changed, s) }
    }
    pan.ended = { [weak self] cancelled in self?.lassoStep(cancelled ? .cancelled : .ended, nil) }
    pan.isEnabled = false
    v.addGestureRecognizer(pan)
    lasso.pan = pan
    // A touch the watcher follows (the lasso's loop, a drag on the selection) doesn't scroll; two fingers still do.
    v.panGestureRecognizer.require(toFail: pan)
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(pasteHold(_:)))
    hold.minimumPressDuration = Self.pasteHold
    hold.allowableMovement = 8
    hold.delegate = self
    v.addGestureRecognizer(hold)
    lasso.hold = hold
    lasso.loopLayer.lineWidth = 1.5
    lasso.loopLayer.lineDashPattern = [5, 5]
    lasso.loopLayer.zPosition = 10
    v.layer.addSublayer(lasso.loopLayer)
    lasso.shapeLayer.zPosition = 9
    v.layer.addSublayer(lasso.shapeLayer)
    v.addSubview(lasso.chrome)
    installLock(on: v)
    installShotFlash(on: v)
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    // The hold and every touch watcher (hold-to-shape, the shape eraser, a finger held on a lock)
    // run alongside everything; the lasso alongside PencilKit's own recognisers (scrolling waits for
    // it to fail instead).
    if g === lasso.hold || g === textEdit.tap || (g is StrokeWatcher && g !== lasso.pan) { return true }
    if g === lasso.pan { return other !== canvas?.panGestureRecognizer }
    return false
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    // A tap inside the text box being typed in is the text box's own (placing the cursor), not "done".
    if g === textEdit.tap, let hit = touch.view {
      for own in textEdit.ownViews where hit === own || hit.isDescendant(of: own) { return false }
    }
    // A touch that took hold of the selection is the selection's alone: no tap on what's under it, no Paste.
    if g === textEdit.tap || g === lasso.hold, claim(touch) != nil { return false }
    // Not on a locked item: that hold unlocks it.
    if g === lasso.hold, let canvas, item(at: Pt(touch.location(in: canvas)) / zoom, locked: true) != nil { return false }
    return true
  }

  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    if g === lasso.hold { return !Clipboard.items.isEmpty && !parent.viewOnly && textEdit.view == nil }
    // A text box picked up but not yet typed in is carried by a drag and opened by a tap; once
    // typing, touches in it are the text's own.
    if let v = textEdit.view, g.view === v { return !textEdit.typing }
    return true
  }

  private func world(_ g: UIGestureRecognizer) -> CGPoint {
    guard let canvas else { return .zero }
    let p = g.location(in: canvas)  // content coordinates (the scroll view's bounds origin is its offset)
    return CGPoint(x: p.x / canvas.zoomScale, y: p.y / canvas.zoomScale)
  }

  // MARK: Drawing the loop and moving

  /// One step of the watcher's touch: [t] is nil when it ends (it ends where it last was). A touch
  /// that took hold of the selection drags it; any other, with the lasso, draws the loop.
  func lassoStep(_ phase: UIGestureRecognizer.State, _ t: UITouch?) {
    guard let canvas else { return }
    if let t {
      let q = t.location(in: canvas)
      lasso.lastAt = CGPoint(x: q.x / canvas.zoomScale, y: q.y / canvas.zoomScale)
    }
    let p = Pt(lasso.lastAt)
    switch phase {
    case .began:
      if let t, let grab = claim(t) {
        beginDrag(grab, at: p)
      } else {
        clearSelection()
        lasso.loop = [p]
      }
    case .changed:
      if lasso.drag != nil {
        continueDrag(to: p)
      } else if !lasso.loop.isEmpty {
        lasso.loop.append(p)
        drawLoop()
      }
    case .ended, .cancelled, .failed:
      if lasso.drag != nil {
        endDrag(cancelled: phase != .ended)
      } else if phase == .cancelled {
        // A second finger came down: it's a pinch or scroll, not a loop.
        lasso.loop = []
        lasso.loopLayer.path = nil
      } else {
        finishLasso()
      }
    default: break
    }
  }

  /// The loop is done (Android's `finishLasso`): the screenshot lasso takes its picture; a tap picks
  /// up what's under it; the lasso whatever its loop touches; free form whatever the path passes
  /// over, plus everything in the loop if it comes back round. A fill and its outline come together.
  private func finishLasso() {
    let path = lasso.loop
    lasso.loop = []
    lasso.loopLayer.path = nil
    let length = Geo.pathLength(path) * zoom
    if LassoSettings.shot {
      if length >= Lasso.tapLength { takeScreenshot(path) }
      return
    }
    if length < Lasso.tapLength {
      // A tap with the lasso picks up whatever is under it, never a whole PDF page.
      if let end = path.last, let item = item(at: end, anyLock: LassoSettings.pickLocked, filter: LassoSettings.hits) { selectGroup(item) }
      return
    }
    guard let area = Rect.around(path) else { return }
    let free = LassoSettings.free, pickLocked = LassoSettings.pickLocked
    let reach = Lasso.freeReach / zoom
    let loop = !free || Lasso.loopCloses(path, zoom: zoom)
    let near = area.outset(reach)
    let touched = pageItems.filter { item in
      guard !item.locked || pickLocked, LassoSettings.hits(item.pen), item.bounds.intersects(near) else { return false }
      return (loop && item.bounds.intersects(area) && Self.lassoTouches(item, path)) || (free && Self.touchedBy(item, path, reach))
    }
    let picked = withFills(touched.map(\.id))
    if !picked.isEmpty { UISelectionFeedbackGenerator().selectionChanged() }
    setSelection(Set(picked), menu: true)
  }

  /// Whether the lasso loop [poly] picks up [item]: anything it touches. A whole PDF page is never
  /// picked up, however much of it the loop holds: it's the page itself.
  private static func lassoTouches(_ item: PageItem, _ poly: [Pt]) -> Bool {
    switch item {
    case .ink(let s): Lasso.touchesPath(s.inputs.points.map { Pt($0.x, $0.y) }, poly)
    case .shape(let s): s.geometry.paths(s.size).contains { Lasso.touchesPath($0, poly) }
    case .picture(let p): !p.pdfPage && Lasso.touchesRect(p.rect, poly)
    case .text: Lasso.touchesRect(item.bounds, poly)
    }
  }

  /// Free form: whether the traced [path] passes over or within [r] of [item].
  private static func touchedBy(_ item: PageItem, _ path: [Pt], _ r: Float) -> Bool {
    switch item {
    case .ink(let s): Lasso.nearPath(s.inputs.points.map { Pt($0.x, $0.y) }, path, r)
    case .shape(let s): s.geometry.paths(s.size).contains { Lasso.nearPath($0, path, r) }
    case .picture(let p): !p.pdfPage && Lasso.nearRect(p.rect, path, r)
    case .text: Lasso.nearRect(item.bounds, path, r)
    }
  }

  /// A fill and the drawing around it move as one: [ids] with every area fill outlined by something
  /// in it, and every outline stroke of any fill in it. Only the eraser treats them apart.
  func withFills(_ ids: [String], pickLocked: Bool = LassoSettings.pickLocked) -> [String] {
    let known = fills.map(\.picture).map { FillGroup.Fill(id: $0.id, walls: $0.walls, locked: $0.locked) }
    if known.isEmpty { return ids }
    var locked: [String: Bool] = [:]
    for item in pageItems { locked[item.id] = item.locked }
    return FillGroup.with(ids, fills: known, isLocked: { locked[$0] }, pickLocked: pickLocked)
  }

  /// Picks up [item], with the fill it outlines or the outline around it if it's a fill.
  func selectGroup(_ item: PageItem) {
    setSelection(Set(withFills([item.id])), menu: true)
  }

  func clearSelection() {
    endThicknessPreview()
    lasso.picked = []
    lasso.bounds = nil
    lasso.loop = []
    lasso.loopLayer.path = nil
    lasso.soft = false
    lasso.menuClosed = false
    lasso.menuTicket += 1
    drawChrome()
    parent.onSelection(nil)
  }

  /// The lasso is its closed, softly filled loop; free form a dotted trail of where she traced
  /// (closing up only once it comes round); the screenshot lasso shows the rectangle it will take.
  private func drawLoop() {
    guard let canvas, let first = lasso.loop.first else { return }
    let z = canvas.zoomScale
    let path = CGMutablePath()
    path.move(to: CGPoint(x: CGFloat(first.x) * z, y: CGFloat(first.y) * z))
    for p in lasso.loop.dropFirst() { path.addLine(to: CGPoint(x: CGFloat(p.x) * z, y: CGFloat(p.y) * z)) }
    let open = LassoSettings.free && !Lasso.loopCloses(lasso.loop, zoom: Float(z))
    if !open { path.closeSubpath() }
    if LassoSettings.shot, let area = Rect.around(lasso.loop) {
      path.addRect(CGRect(x: CGFloat(area.left) * z, y: CGFloat(area.top) * z, width: CGFloat(area.width) * z, height: CGFloat(area.height) * z))
    }
    lasso.loopLayer.strokeColor = SelectionChromeView.accent.cgColor
    lasso.loopLayer.fillColor = open && !LassoSettings.shot ? UIColor.clear.cgColor : SelectionChromeView.accent.withAlphaComponent(0x1C / 255).cgColor
    lasso.loopLayer.path = path
  }

  func redrawSelection() {
    if !lasso.loop.isEmpty { drawLoop() }
    drawChrome()
    reportSelection()
  }

  /// Tells the screen what's picked up and where, for the selection menu (Android's `publishSelection`).
  func reportSelection() {
    guard let canvas, let b = lasso.bounds, lasso.drag == nil, !lasso.menuClosed else { return }
    let z = canvas.zoomScale
    let content = CGRect(x: b.minX * z, y: b.minY * z, width: b.width * z, height: b.height * z).insetBy(dx: -8, dy: -8)
    let items = pickedItems
    var info = SelectionInfo(rect: canvas.convert(content, to: nil), count: items.count, rotatable: canRotate)
    for item in items {
      switch item {
      case .ink(let s):
        info.hasDrawing = true
        if info.color == nil { info.color = UInt32(bitPattern: s.color) | 0xFF00_0000 }
        if info.lineSize == nil { info.lineSize = s.size }
      case .shape(let s):
        info.hasDrawing = true
        if info.color == nil { info.color = UInt32(bitPattern: s.color) | 0xFF00_0000 }
        if info.lineSize == nil { info.lineSize = s.size }
        if info.line == nil { info.line = s.line }
      case .text(let t):
        if info.color == nil { info.color = UInt32(bitPattern: t.color) }
      case .picture:
        info.hasImage = true
      }
    }
    if items.count == 1, case .text(let t) = items[0] { info.textId = t.id }
    if items.count == 1, case .picture(let p) = items[0] { info.croppable = CropEdit.croppable(p) && !p.isFill }
    info.locked = !items.isEmpty && items.allSatisfy(\.locked)
    parent.onSelection(info)
  }

  // MARK: The menu's actions

  var pickedStrokes: [InkStroke] { stored.map(\.stroke).filter { lasso.picked.contains($0.id) } }

  private func select(_ items: [PageItem], menu: Bool? = nil) {
    setSelection(Set(items.map(\.id)), menu: menu)
  }

  func copySelection() {
    let items = pickedItems
    guard !items.isEmpty else { return }
    Clipboard.items = items
    parent.onHint(items.count == 1 ? L("copied_hold_anywhere_to_paste_it") : L("copied_n_items_hold_anywhere_to", items.count))
  }

  /// Cuts the selection: onto the clipboard, then off the page (undo brings it back).
  func cutSelection() {
    let items = pickedItems
    guard !items.isEmpty else { return }
    Clipboard.items = items
    deleteSelection()
    parent.onHint(items.count == 1 ? L("cut_hold_anywhere_to_paste_it_2") : L("cut_n_items_hold_anywhere_to", items.count))
  }

  func deleteSelection() {
    let items = pickedItems
    clearSelection()
    commit(remove: items, add: [])
  }

  /// Copies of [items] moved by [m], with new ids, on top of everything. A fill copied with its
  /// outline keeps outlining the copies, so the copy is one filled shape too.
  private func copiesOf(_ items: [PageItem], _ m: Affine) -> [PageItem] {
    var ids: [String: String] = [:]
    for item in items { ids[item.id] = newId() }
    var z = topZ
    return items.map { item in
      z += 1
      let id = ids[item.id] ?? newId()
      switch item.transformed(m) {
      case .ink(var s):
        s.id = id
        s.z = z
        return .ink(s)
      case .shape(var s):
        s.id = id
        s.z = z
        return .shape(s)
      case .text(var t):
        t.id = id
        t.z = z
        return .text(t)
      case .picture(let p):
        return .picture(p.copy(id: id, z: z, walls: FillGroup.copiedWalls(p.walls, ids: ids)))
      }
    }
  }

  /// Copies a little down and to the right, and picks the copies up instead (Android: 24 units).
  func duplicateSelection() {
    let copies = copiesOf(pickedItems, .translate(Self.duplicateOffset, Self.duplicateOffset))
    guard !copies.isEmpty else { return }
    commit(remove: [], add: copies)
    select(copies)
  }

  /// A rectangle round what's picked up, drawn with the pen in use (its colour, thickness and line),
  /// a little clear of it, in one undo step. It joins the selection, so the two move on together.
  func boxSelection() {
    guard let bounds = lasso.bounds else { return }
    let b = TaliCore.Rect(bounds)
    let pen = shapePen
    let gap = Self.frameGap + pen.size / 2
    let box = ShapeGeometry.poly(points: [Pt(b.left - gap, b.top - gap), Pt(b.right + gap, b.top - gap), Pt(b.right + gap, b.bottom + gap), Pt(b.left - gap, b.bottom + gap)], closed: true)
    var frame = ShapeRow(id: newId(), geometry: box, pen: pen.type.rawValue, color: pen.color, size: pen.size)
    frame.z = topZ + 1
    let kept = lasso.picked
    commit(remove: [], add: [.shape(frame)])
    setSelection(kept.union([frame.id]), menu: nil)
  }

  // MARK: Hold to paste

  @objc func pasteHold(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began, let canvas, !Clipboard.items.isEmpty else { return }
    let p = world(g)
    lasso.pasteAt = p
    // Whatever the touch had started there (a lasso, a dot of ink) is dropped.
    lasso.loop = []
    lasso.loopLayer.path = nil
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let z = canvas.zoomScale
    parent.onPasteOffer(canvas.convert(CGPoint(x: p.x * z, y: p.y * z), to: nil))
  }

  /// Pastes what's copied centred on where the hold was, picked up so it can be moved into place.
  func pasteAtOffer() {
    parent.onPasteOffer(nil)
    guard let at = lasso.pasteAt else { return }
    lasso.pasteAt = nil
    let items = Clipboard.items.sorted { $0.z < $1.z }
    guard let b = items.map(\.bounds).reduce(nil, { (all: TaliCore.Rect?, r) in all?.union(r) ?? r }) else { return }
    let copies = copiesOf(items, .translate(Float(at.x) - b.center.x, Float(at.y) - b.center.y))
    commit(remove: [], add: copies)
    select(copies)
  }

  // MARK: The menu's ⋯ part: colour, thickness, order, mirror

  /// Replaces what's picked up with [change] applied to each item, as one undo step, still picked up.
  private func change(_ change: (PageItem) -> PageItem) {
    let items = pickedItems
    guard !items.isEmpty else { return }
    let changed = items.map(change)
    commit(remove: items, add: changed)
    select(changed)
  }

  func recolourSelection(_ argb: UInt32) {
    let color = Int32(bitPattern: argb)
    change { item in
      switch item {
      case .ink(var s):
        let c = argb | 0xFF00_0000
        s.color = Int32(bitPattern: s.pen == .HIGHLIGHTER ? (c & 0x00FF_FFFF) | (PenSlot.highlighterAlpha << 24) : c)
        s.locked = false
        return .ink(s)
      case .shape(let s): return .shape(s.recolored(color))
      case .text(var t):
        t.color = color
        return .text(t)
      case .picture: return item
      }
    }
  }

  /// Changes how the writing and shapes picked up are drawn: [size] thick and/or in [line] style
  /// (nil leaves that as it is). Pictures and text keep theirs.
  func restyleSelection(size: Float?, line: String?) {
    endThicknessPreview()
    // Slid back to where it was: nothing to save.
    guard size != nil || line != nil else { return }
    change { item in
      switch item {
      case .ink(var s):
        s.size = size ?? s.size
        s.locked = false
        return .ink(s)
      case .shape(var s):
        s.size = size ?? s.size
        s.line = line ?? s.line
        s.locked = false
        return .shape(s)
      case .text, .picture: return item
      }
    }
  }

  /// Mirrors what's picked up around its own middle, left to right or upside down (one undo step).
  /// Writing, shapes and area fills flip; pictures and text move to their mirrored places but keep
  /// facing the right way.
  func mirrorSelection(horizontal: Bool) {
    guard let b = lasso.bounds else { return }
    let m = Affine.scaleAround(Pt(Float(b.midX), Float(b.midY)), horizontal ? -1 : 1, horizontal ? 1 : -1)
    change { item in
      switch item {
      case .picture(let p): return .picture(p.mirrored(m, horizontal: horizontal))
      case .text:
        let c = item.bounds.center, to = m.apply(c)
        return item.transformed(.translate(to.x - c.x, to.y - c.y))
      case .ink, .shape: return item.transformed(m)
      }
    }
  }

  /// Brings what's picked up in front of everything or sends it behind everything, keeping its own
  /// order. Pictures brought forward can cover shapes and text; sent back, they sit behind like paper.
  func arrangeSelection(toFront: Bool) {
    let items = pickedItems
    guard !items.isEmpty else { return }
    func entry(_ item: PageItem) -> Arrange.Item { Arrange.Item(id: item.id, z: item.z, picture: item.picture != nil, front: item.picture?.front ?? false) }
    let others = pageItems.filter { !lasso.picked.contains($0.id) }.map(entry)
      + (pages?.pages.under.pdfPages.map { Arrange.Item(id: $0.id, z: 0, picture: true) } ?? [])
    guard let plan = Arrange.plan(items.map(entry), others: others, toFront: toFront, top: topZ) else {
      parent.onHint(toFront ? L("already_in_front") : L("already_at_the_back"))
      return
    }
    var places: [String: (z: Int64, front: Bool)] = [:]
    for p in plan { places[p.id] = (p.z, p.front) }
    change { item in
      guard let place = places[item.id] else { return item }
      if case .picture(let p) = item { return .picture(p.inFront(place.front, z: place.z)) }
      return item.withZ(place.z)
    }
    shapeZ = max(shapeZ, topZ)
    parent.onHint(toFront ? L("brought_to_the_front") : L("sent_to_the_back"))
  }

  // MARK: Thickness, shown while the slider moves

  /// The menu's thickness slider is moving: the selection is shown [size] thick straight away
  /// (saved once the slider is let go, in `restyleSelection`).
  func previewThickness(_ size: Float) {
    guard let canvas, lasso.bounds != nil, lasso.drag == nil else { return }
    if lasso.before == nil {
      lasso.before = canvas.drawing
      liftShapes()
    }
    guard let before = lasso.before else { return }
    loading = true
    canvas.drawing = PKDrawing(strokes: before.strokes.enumerated().map { i, pk in
      guard i < stored.count, lasso.picked.contains(stored[i].stroke.id) else { return pk }
      var s = stored[i].stroke
      s.size = size
      return s.pkStroke(mask: mask(for: s))
    })
    loading = false
    showThickness(size)
  }

  func endThicknessPreview() {
    guard lasso.drag == nil, let before = lasso.before, let canvas else { return }
    lasso.before = nil
    loading = true
    canvas.drawing = before
    loading = false
    restoreLifted()
    dropShapes()
  }
}

func joined(_ a: CGRect?, _ b: CGRect?) -> CGRect? {
  switch (a, b) {
  case let (a?, b?): a.union(b)
  case let (a?, nil): a
  case let (nil, b?): b
  default: nil
  }
}

extension NoteCanvas.Coordinator {
  func unionOf(_ strokes: [InkStroke]) -> CGRect? {
    strokes.reduce(nil) { joined($0, CGRect($1.bounds)) }
  }

  func unionOf(_ list: [ShapeRow]) -> CGRect? {
    list.reduce(nil) { all, s in joined(all, s.geometry.bounds(s.size).map { CGRect($0) }) }
  }
}
