import PencilKit
import TaliCore
import UIKit

/// Pictures and PDF pages put into an open notebook (Android's `insertImage` and `insertPages`): from
/// Insert, the camera, other apps and drops. Each addition is one undo step.
extension NoteCanvas.Coordinator {
  /// What shows of the world on screen.
  var visibleWorld: Rect {
    guard let canvas else { return Rect(0, 0, 1, 1) }
    let z = max(canvas.zoomScale, 0.01), b = canvas.bounds
    return Rect(Float(b.minX / z), Float(b.minY / z), Float(b.maxX / z), Float(b.maxY / z))
  }

  /// A picture [index] of a batch, centred on [at] (a point in the canvas) or the middle of the view.
  func insertPicture(_ page: Library.ImportedPage, at: CGPoint? = nil, index: Int = 0) {
    guard let canvas else { return }
    let z = Float(max(canvas.zoomScale, 0.01))
    let world = at.map { Pt(Float($0.x) / z, Float($0.y) / z) }
    var rect = Placing.picture(
      size: Pt(Float(page.width), Float(page.height)), visible: visibleWorld, at: world, index: index, zoom: z, maxUnitsPerPixel: Float(2 / canvas.traitCollection.displayScale))
    if paged { rect = Placing.ontoPage(rect, pages: layout, count: pageCount) }
    addPictures([PictureRow(id: newId(), z: nextZ(), file: page.file, rect: rect)], pageCount: pageCount)
  }

  /// PDF pages: on a paged notebook a page each, from the last page if it's empty; on an endless
  /// canvas one under the other below the writing, the first shown across the screen.
  func insertPages(_ pages: [Library.ImportedPage]) {
    guard let canvas, !pages.isEmpty else { return }
    let sizes = pages.map { Pt(Float($0.width / CGFloat(ExportPages.ptPerUnit)), Float($0.height / CGFloat(ExportPages.ptPerUnit))) }
    var z = nextZ()
    func rows(_ rects: [Rect]) -> [PictureRow] {
      zip(pages, rects).map { p, r in
        defer { z += 1 }
        return PictureRow(id: newId(), z: z, file: p.file, rect: r, pdfPage: true)
      }
    }
    if paged {
      let (start, rects) = Placing.pdfOnPages(sizes, pages: layout, count: pageCount, lastIsEmpty: !hasContent(on: layout.rect(pageCount - 1)))
      addPictures(rows(rects), pageCount: start + pages.count)
      run(.goToPage(start))
      return
    }
    let rects = Placing.pdfOnCanvas(sizes, content: contentBounds, visible: visibleWorld)
    addPictures(rows(rects), pageCount: pageCount)
    let widest = CGFloat(sizes.map(\.x).max() ?? 1)
    let zoom = min(max(canvas.bounds.width * 0.9 / widest, canvas.minimumZoomScale), 1.5)
    canvas.setZoomScale(zoom, animated: false)
    updateContent()
    let first = rects[0]
    canvas.setContentOffset(
      CGPoint(x: (CGFloat(first.center.x) * zoom - canvas.bounds.width / 2), y: CGFloat(first.top) * zoom - parent.topClearance), animated: true)
  }

  /// Everything on the page, as one box (for placing what comes next).
  var contentBounds: Rect? {
    var boxes = stored.compactMap { $0.stroke.inputs.bounds }
    if let under = pages?.pages.under {
      boxes += under.shapes.compactMap { $0.geometry.bounds($0.size) }
      boxes += under.texts.map { Rect($0.x, $0.y, $0.x + $0.width, $0.y + $0.fontSize * TextRow.line) }
      boxes += under.pictures.map(\.row.rect)
      boxes += under.pdfPages.map { Rect(Float($0.rect.minX), Float($0.rect.minY), Float($0.rect.maxX), Float($0.rect.maxY)) }
    }
    return boxes.reduce(nil) { (acc: Rect?, r) in acc?.union(r) ?? r }
  }

  private func hasContent(on page: Rect) -> Bool {
    guard let c = contentBounds, c.intersects(page) else { return false }
    let under = pages?.pages.under
    return stored.contains { $0.stroke.inputs.bounds?.intersects(page) == true }
      || under?.shapes.contains { $0.geometry.bounds($0.size)?.intersects(page) == true } == true
      || under?.texts.contains { Rect($0.x, $0.y, $0.x + $0.width, $0.y + 1).intersects(page) } == true
      || under?.pictures.contains { $0.row.rect.intersects(page) } == true
      || under?.pdfPages.contains { CGRect(page).intersects($0.rect) } == true
  }

  func nextZ() -> Int64 {
    let pics = (pages?.pages.under.pictures.map(\.row.z).max() ?? 0)
    let z = max(stored.map(\.stroke.z).max() ?? 0, shapeZ, pics) + 1
    shapeZ = z
    return z
  }

  /// Adds pictures and sets the page count, as one undo step (undo takes both back).
  func addPictures(_ rows: [PictureRow], pageCount newCount: Int) {
    let oldCount = pageCount
    showPictures(rows, pageCount: max(newCount, pageCount))
    canvas?.undoManager?.registerUndo(withTarget: self) { c in
      MainActor.assumeIsolated {
        c.hidePictures(rows.map(\.id), pageCount: oldCount)
        c.canvas?.undoManager?.registerUndo(withTarget: c) { c2 in
          MainActor.assumeIsolated { c2.addPictures(rows, pageCount: newCount) }
        }
      }
    }
    reportUndo()
  }

  func showPictures(_ rows: [PictureRow], pageCount newCount: Int) {
    guard let pages else { return }
    for p in rows {
      do { try parent.db.put(p.itemRow, in: parent.notebook.id) } catch { CrashNote.log("saving a picture: \(error)") }
      if let sharp = SharpPage.of(p.itemRow) {
        pages.pages.under.pdfPages.append(sharp)
      } else if let pic = placed(p) {
        pages.pages.under.pictures.append(pic)
      }
    }
    setPageCount(newCount)
    touch()
    pages.layer.setNeedsDisplay()
  }

  func hidePictures(_ ids: [String], pageCount newCount: Int) {
    guard let pages else { return }
    let gone = Set(ids)
    pages.pages.under.pictures.removeAll { gone.contains($0.row.id) }
    pages.pages.under.pdfPages.removeAll { gone.contains($0.id) }
    for id in ids { try? parent.db.removeItem(id) }
    setPageCount(newCount)
    touch()
    pages.layer.setNeedsDisplay()
    reportUndo()
  }

  private func setPageCount(_ n: Int) {
    guard paged, n != pageCount else { return }
    pageCount = max(n, 1)
    updateContent()
    persistPages()
  }
}
