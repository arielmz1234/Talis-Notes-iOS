import ImageIO
import PencilKit
import TaliCore
import UIKit
import UniformTypeIdentifiers

/// A filled area as the page draws it: its stored row, its picture, and which of the picture's
/// cells are coloured (a tap on the fill, not just in its box, takes it away or recolours it).
struct FillPicture: @unchecked Sendable, Equatable {
  let row: FillRow
  let image: CGImage
  let covered: [Bool]

  static func == (a: FillPicture, b: FillPicture) -> Bool { a.row == b.row }

  func covers(_ p: Pt) -> Bool {
    guard row.rect.contains(p), image.width > 0, image.height > 0 else { return false }
    let cell = row.cell(at: p, width: image.width, height: image.height)
    return covered[cell.y * image.width + cell.x]
  }

  /// A fill picture read from the app's images folder.
  init?(_ item: ItemRow) {
    guard let row = FillRow(item), !row.file.contains("/"),
      let src = CGImageSourceCreateWithURL(AppFiles.folders.images.appendingPathComponent(row.file) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    let w = image.width, h = image.height
    guard let cg = FillPicture.bitmap(w, h) else { return nil }
    cg.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = cg.data else { return nil }
    let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    self.row = row
    self.image = image
    covered = (0..<(w * h)).map { bytes[$0 * 4 + 3] > 0 }
  }

  /// A new fill of [area] in [colour], its picture saved as Android names and writes it.
  init?(_ area: AreaFill.Area, colour: Int32, id: String, z: Int64) {
    let w = area.width, h = area.height
    guard let cg = FillPicture.bitmap(w, h), let data = cg.data else { return nil }
    let c = UInt32(bitPattern: colour)
    let a = (c >> 24) & 0xFF
    let pixel = [UInt8((c >> 16 & 0xFF) * a / 255), UInt8((c >> 8 & 0xFF) * a / 255), UInt8((c & 0xFF) * a / 255), UInt8(a)]
    let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    for i in 0..<(w * h) where area.cells[i] {
      for k in 0..<4 { bytes[i * 4 + k] = pixel[k] }
    }
    guard let image = cg.makeImage() else { return nil }
    let file = FillRow.fileName(colour: colour, unique: UUID().uuidString.lowercased())
    let url = AppFiles.folders.images.appendingPathComponent(file)
    guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { return nil }
    row = FillRow(id: id, z: z, file: file, rect: area.rect, walls: area.outline)
    self.image = image
    covered = area.cells
  }

  /// A [w] by [h] picture to draw into, its first row at the top.
  static func bitmap(_ w: Int, _ h: Int) -> CGContext? {
    CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  }

  /// Drawn where it sits on the page, mirrored if it was mirrored with its outline.
  func draw(in cg: CGContext) {
    let r = CGRect(row.rect)
    cg.saveGState()
    cg.translateBy(x: row.flipX ? r.maxX : r.minX, y: row.flipY ? r.minY : r.maxY)
    cg.scaleBy(x: row.flipX ? -1 : 1, y: row.flipY ? 1 : -1)
    cg.draw(image, in: CGRect(origin: .zero, size: r.size))
    cg.restoreGState()
  }
}

/// Everything round a tap that can close an area in, handed to the background to be drawn.
private struct FillWalls: @unchecked Sendable {
  var window: Rect
  var ink: PKDrawing
  var shapes: [ShapeRow]
  var texts: [TextRow]
  /// The same lines by id: the ones outlining the filled area move with it.
  var lines: [AreaFill.Wall]

  var isEmpty: Bool { ink.strokes.isEmpty && shapes.isEmpty && texts.isEmpty }

  /// The writing in the window drawn into a mask (Android's `fillPicture`): true where there's a line.
  /// Shapes' own fills aren't walls: only their outlines close an area in.
  func mask() -> [Bool] {
    let (k, w, h) = AreaFill.grid(for: window)
    guard let cg = FillPicture.bitmap(w, h) else { return [] }
    let rect = CGRect(window)
    cg.translateBy(x: 0, y: CGFloat(h))
    cg.scaleBy(x: CGFloat(k), y: -CGFloat(k))
    cg.translateBy(x: -rect.minX, y: -rect.minY)
    if !ink.strokes.isEmpty, let image = ink.image(from: rect, scale: CGFloat(k)).cgImage {
      cg.saveGState()
      cg.translateBy(x: rect.minX, y: rect.maxY)
      cg.scaleBy(x: 1, y: -1)
      cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
      cg.restoreGState()
    }
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(UIColor.black.cgColor)
    for s in shapes {
      for line in s.strokes where line.count > 1 { cg.addLines(between: line.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }) }
      cg.setLineWidth(CGFloat(s.size))
      cg.strokePath()
    }
    if !texts.isEmpty {
      UIGraphicsPushContext(cg)
      for t in texts {
        let box = TextLook.frame(t)
        TextLook.attributed(t).draw(with: CGRect(x: box.minX, y: box.minY, width: box.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
      }
      UIGraphicsPopContext()
    }
    guard let data = cg.data else { return [] }
    let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    return (0..<(w * h)).map { bytes[$0 * 4 + 3] > 40 }
  }
}

@MainActor
struct FillToolState {
  var tap: UITapGestureRecognizer?
  /// An area is being worked out: another tap waits for it.
  var filling = false
  let alongside = RecognisesAlongside()
}

/// Lets the fill tool's tap be recognised whatever PencilKit's own recognisers make of the touch.
final class RecognisesAlongside: NSObject, UIGestureRecognizerDelegate {
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// The Fill tool (Android's `Tool.FILL`, `fillAt`): a tap inside a closed shape gives the shape a
/// fill of its own; a tap inside an area her writing closes in puts a picture of that area behind
/// the writing; with no colour chosen a tap takes a fill away.
extension NoteCanvas.Coordinator {
  var fills: [FillPicture] { pages?.pages.under.fills ?? [] }

  func installFillTool(on v: PKCanvasView) {
    let tap = UITapGestureRecognizer(target: self, action: #selector(fillTapped(_:)))
    tap.isEnabled = false
    tap.cancelsTouchesInView = false
    tap.delegate = fillTool.alongside
    v.addGestureRecognizer(tap)
    fillTool.tap = tap
  }

  /// The pen fills; a finger only where fingers draw.
  func applyFillTool() {
    guard let canvas, let tap = fillTool.tap else { return }
    tap.isEnabled = parent.tool == .fill && !parent.viewOnly
    let fingers: Bool
    switch canvas.drawingPolicy {
    case .anyInput: fingers = true
    case .pencilOnly: fingers = false
    default: fingers = !UIPencilInteraction.prefersPencilOnlyDrawing
    }
    let types: [UITouch.TouchType] = fingers ? [.direct, .pencil] : [.pencil]
    tap.allowedTouchTypes = types.map { NSNumber(value: $0.rawValue) }
  }

  @objc func fillTapped(_ g: UITapGestureRecognizer) {
    guard let canvas, g.state == .ended else { return }
    let q = g.location(in: canvas)
    fillAt(Pt(Float(q.x / canvas.zoomScale), Float(q.y / canvas.zoomScale)))
  }

  func fillAt(_ p: Pt) {
    guard let canvas else { return }
    let colour = ShapeSettings.fillArgb
    let all = shapes
    // The topmost closed shape the tap is inside. Nothing running through it: it gets a fill of its
    // own. A line (or anything) through it splits it, so the area round the tap is filled instead,
    // unless that turns out to be nearly the whole shape (a label inside it).
    let shape = FillTap.shape(at: p, in: all)
    let split = shape.map { s in
      let box = s.geometry.bounds(s.size)
      let near = (stored.map(\.stroke) + lockedInk).filter { st in box.map { $0.intersects(st.bounds) } ?? false }
      return FillTap.runsThrough(s, ink: near.map { $0.inputs.points.map { Pt($0.x, $0.y) } }, shapes: all)
    } ?? false
    if let shape, !split || (colour == nil && shape.fill != nil) {
      if shape.fill != colour { commitFill(shapes: all.map { $0.id == shape.id ? $0.filled(colour) : $0 }, fills: fills) }
      return
    }
    // A fill picture already there: taken away, or replaced by the new colour below.
    let old = Set(fills.filter { $0.covers(p) }.map(\.row.id))
    guard let colour else {
      if old.isEmpty { parent.onHint(L("tap_a_filled_shape_or_area_2")) } else { commitFill(shapes: all, fills: fills.filter { !old.contains($0.row.id) }) }
      return
    }
    if fillTool.filling { return }
    fillTool.filling = true
    let page = paged ? layout.rect(min(max(layout.indexAt(p.y), 0), pageCount - 1)) : nil
    let window = AreaFill.window(around: p, page: page)
    let strokes = canvas.drawing.strokes
    let inWindow = stored.indices.filter { $0 < strokes.count && stored[$0].stroke.bounds.intersects(window) }
    let wallShapes = all.filter { $0.geometry.bounds($0.size)?.intersects(window) ?? false }
    let frame = CGRect(window)
    // Locked writing closes an area in like any other (it's drawn by the page, not by PencilKit).
    let wallInk = inWindow.map { stored[$0].stroke } + lockedInk.filter { $0.bounds.intersects(window) }
    let walls = FillWalls(
      window: window, ink: PKDrawing(strokes: inWindow.map { strokes[$0] } + lockedInk.filter { $0.bounds.intersects(window) }.map { $0.pkStroke(mask: mask(for: $0)) }),
      shapes: wallShapes, texts: texts.filter { TextLook.frame($0).intersects(frame) },
      lines: wallInk.map { s in AreaFill.Wall(id: s.id, paths: [s.inputs.points.map { Pt($0.x, $0.y) }], size: s.size) }
        + wallShapes.map { AreaFill.Wall(id: $0.id, paths: $0.geometry.paths($0.size), size: $0.size) })
    // A shape split by a line: filling nearly all of it (90%) still gives it a fill of its own.
    let whole = shape.map { abs(Geo.polygonArea($0.outline)) * 0.9 }
    let id = newId()
    let z = max(stored.map(\.stroke.z).max() ?? 0, shapeZ) + 1
    DispatchQueue.global(qos: .userInitiated).async {
      let found = AreaFill.find(mask: walls.mask(), window: walls.window, at: p, walls: walls.lines, whole: whole)
      let picture: FillPicture? = if case .area(let area) = found { FillPicture(area, colour: colour, id: id, z: z) } else { nil }
      DispatchQueue.main.async { [weak self] in self?.finishFill(found, picture, shape: shape, replacing: old, colour: colour, nothingToClose: walls.isEmpty) }
    }
  }

  private func finishFill(_ found: AreaFill.Found, _ picture: FillPicture?, shape: ShapeRow?, replacing old: Set<String>, colour: Int32, nothingToClose: Bool) {
    fillTool.filling = false
    let live = shape.flatMap { s in shapes.first { $0.id == s.id } }
    switch found {
    case .open:
      parent.onHint(nothingToClose ? L("draw_around_an_area_first_or") : L("that_area_isn_t_closed_close"))
    case .wholeShape:
      if let live, live.fill != colour { commitFill(shapes: shapes.map { $0.id == live.id ? $0.filled(colour) : $0 }, fills: fills) }
    case .area:
      guard let picture else {
        CrashNote.log("a fill picture couldn't be saved")
        return
      }
      shapeZ = max(shapeZ, picture.row.row.z)
      // The shape's own fill would cover the part filled now (fill pictures sit behind shapes): it goes.
      let unfilled = shapes.map { $0.id == live?.id && $0.fill != nil ? $0.filled(nil) : $0 }
      commitFill(shapes: unfilled, fills: fills.filter { !old.contains($0.row.id) } + [picture])
    }
  }

  /// Makes [newFills] the notebook's fill pictures: new and changed ones are saved, missing ones removed.
  func setFills(_ newFills: [FillPicture]) {
    guard let pages else { return }
    let before = pages.pages.under.fills
    if before == newFills { return }
    let keep = Set(newFills.map(\.row.id))
    let had = Dictionary(before.map { ($0.row.id, $0.row) }, uniquingKeysWith: { a, _ in a })
    do {
      for f in before where !keep.contains(f.row.id) { try parent.db.removeItem(f.row.id) }
      for f in newFills where had[f.row.id] != f.row { try parent.db.put(f.row.row, in: parent.notebook.id) }
    } catch {
      CrashNote.log("saving fills: \(error)")
    }
    pages.pages.under.fills = newFills
    pages.layer.setNeedsDisplay()
    touch()
  }

  /// One change by the fill tool (shapes' own fills and fill pictures together), as one undo step.
  private func commitFill(shapes newShapes: [ShapeRow], fills newFills: [FillPicture]) {
    let before = (shapes, fills)
    if before.0 == newShapes && before.1 == newFills { return }
    setShapes(newShapes)
    setFills(newFills)
    registerFillChange(from: before, to: (newShapes, newFills))
  }

  private func registerFillChange(from before: ([ShapeRow], [FillPicture]), to after: ([ShapeRow], [FillPicture])) {
    canvas?.undoManager?.registerUndo(withTarget: self) { c in
      MainActor.assumeIsolated {
        c.clearSelection()
        c.setShapes(before.0)
        c.setFills(before.1)
        c.registerFillChange(from: after, to: before)
        c.reportUndo()
      }
    }
    reportUndo()
  }
}
