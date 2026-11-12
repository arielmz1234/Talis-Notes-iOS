import TaliCore
import UIKit

/// One drag's snapping (Android's `snapTargets`, `snapMoving`, `snap` and `snapGuides`).
struct SnapState {
  var session = SnapSession(Snapping.contact)
  /// What's on screen that the thing being moved or drawn can snap to (gathered when it starts).
  var targets: [SnapFeatures] = []
  /// The selection's own snapping features where the move started, or nil when it doesn't snap.
  var moving: SnapFeatures?
  /// The guides showing now: dashed lines where things line up, one small cross where they touch.
  var guides: [SnapGuide] = []
  /// A new shape's first point: whether it sits on another shape, and what it lined up with.
  var startStuck: Pt?
  var startGuides: [SnapGuide] = []
}

enum Snapping {
  /// Touching catches from this far on screen, lining up from [align] (Android's `SNAP_DP`, `ALIGN_DP`).
  static let contact: Float = 14
  static let align: Float = 8
  static let maxTargets = 250
}

/// Snapping while moving, resizing or drawing near other shapes, pictures and text (Android's
/// `startMoveSnap`, `moveSelectionTo`, `gatherSnapTargets`, `showSnap`): a firm lock for line ends
/// and corners, shown as a small cross; a softer one for sides and middles, shown as dashed guides.
/// Handwriting isn't snapped to; picked up on its own it lines up by the middle of its box.
extension NoteCanvas.Coordinator {
  private func newSession() -> SnapSession { SnapSession(Snapping.contact / zoom, align: Snapping.align / zoom) }

  /// What can be snapped to: shapes, pictures and text in view, apart from [skip]. Only what's on
  /// screen: lining up with something out of view would hold for no reason she can see.
  private func targets(skipping skip: Set<String>) -> [SnapFeatures] {
    guard LassoSettings.snapShapes else { return [] }
    let view = visibleWorld
    return pageItems.lazy.filter { !skip.contains($0.id) && $0.bounds.intersects(view) }.compactMap(\.snapFeatures).prefix(Snapping.maxTargets).map { $0 }
  }

  /// A drag that snaps begins (a dot, a new shape): what's in view apart from [skip] is gathered.
  func startSnap(skipping skip: Set<String>) {
    lasso.snap = SnapState(session: newSession(), targets: targets(skipping: skip))
  }

  /// A move or a resize begins: shapes, pictures and text snap by their own features; handwriting
  /// picked up on its own lines up by the middle of its box.
  func startMoveSnap() {
    startSnap(skipping: lasso.picked)
    guard LassoSettings.snapShapes else { return }
    let items = pickedItems
    let parts = items.compactMap(\.snapFeatures)
    if !parts.isEmpty {
      let all = SnapFeatures.of(parts)
      // A big selection just lines up by its box (checking every corner of every part would be slow).
      lasso.snap.moving = all.points.count > 80 || all.segments.count > 600 ? SnapFeatures(points: [], segments: [], box: all.box) : all
    } else if let box = items.map(\.bounds).reduce(nil, { (all: Rect?, r) in all?.union(r) ?? r }) {
      lasso.snap.moving = .middleOf(box)
    }
  }

  /// Shows [guides] at the end of a frame's snapping (one cross at most, where the thing being moved
  /// touches now; lining-up guides all show), with a light tick when something first locks on.
  func showSnap(_ guides: [SnapGuide]) {
    let touch = guides.last(where: \.isTouch)
    let shown = guides.filter { !$0.isTouch } + (touch.map { [$0] } ?? [])
    if !shown.isEmpty && lasso.snap.guides.isEmpty { UISelectionFeedbackGenerator().selectionChanged() }
    lasso.snap.guides = shown
    // The frame is done: note what she pulled free of, and start the next one at the zoom now.
    lasso.snap.session.end()
    lasso.snap.session.begin(contact: Snapping.contact / zoom, align: Snapping.align / zoom)
  }

  func endSnap() {
    let showing = !lasso.snap.guides.isEmpty
    lasso.snap = SnapState()
    if showing { drawChrome() }
  }

  // MARK: Drawing a shape

  /// A new shape can start right on another one (a line from a corner or off an edge); not touching
  /// anything, it starts lined up with other shapes' sides, middles and corners.
  func snapShapeStart(_ p: Pt) -> Pt {
    startSnap(skipping: [])
    let start = Snap.shapeStart(p, lasso.snap.targets, contact: Snapping.contact / zoom, align: Snapping.align / zoom)
    lasso.snap.startStuck = start.stuck ? start.at : nil
    lasso.snap.startGuides = start.guides
    return start.at
  }

  /// Where the drag drawing a shape ends, and whether its end is kept exactly (it locked onto or
  /// lined up with something, so a line doesn't go back to its tidy angle).
  func snapShapeEnd(from start: Pt, to raw: Pt, source: ShapeSource) -> (at: Pt, keepEnd: Bool) {
    let end = Snap.shapeEnd(start: start, raw: raw, fromPoint: source.drawnFromPoint, asLine: source.drawnAsLine, lasso.snap.targets, lasso.snap.session)
    showSnap((lasso.snap.startStuck.map { [SnapGuide.touch($0)] } ?? []) + lasso.snap.startGuides + end.guides)
    drawChrome()
    return (end.at, !end.guides.isEmpty)
  }

  // MARK: Hold to shape

  /// A line just made by hold-to-shape starts exactly on another shape it was drawn from.
  func snapLiveLineStart(_ a: Pt) -> Pt {
    startSnap(skipping: [])
    lasso.snap.startStuck = Snap.point(a, lasso.snap.targets, newSession())
    return lasso.snap.startStuck ?? a
  }

  /// Its end follows the pen: onto another shape's corner or edge, else on its tidy angle, sliding
  /// along to line up with other shapes.
  func snapLiveLineEnd(from a: Pt, pen: Pt) -> Pt {
    let end = Snap.liveLineEnd(from: a, pen: pen, lasso.snap.targets, lasso.snap.session)
    showSnap((lasso.snap.startStuck.map { [SnapGuide.touch($0)] } ?? []) + end.guides)
    drawChrome()
    return end.at
  }
}

extension ShapeSource {
  /// Drawn out from the point it attaches at (supports, moments): only its start snaps.
  var drawnFromPoint: Bool {
    switch self {
    case .kind(let k): k.drawnFromPoint
    case .pack(let s): s.drawnFromPoint
    case .custom: false
    }
  }

  /// Drawn like a line (lines, arrows, dimensions, point loads, fixed supports): its end snaps like a line's.
  var drawnAsLine: Bool {
    switch self {
    case .kind(let k): k.drawnAsLine
    case .pack(let s): s.drawnAsLine
    case .custom: false
    }
  }
}
