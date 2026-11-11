import PDFKit
import PencilKit
import TaliCore
import UIKit

/// PDFs and pictures added from the library's + (Android's `Imports` and `NotesRepository.importPdf`):
/// each becomes an item of its own straight away, its pages the shape of its first page or picture,
/// each page a picture filling it (a PDF page's picture named `pdf-<pdf>-p<page>-<uuid>.jpg`, the PDF
/// kept beside them as `pdf-<pdf>.pdf`, so it can be drawn sharp later and backups keep the link),
/// with its library preview drawn.
@MainActor
extension Library {
  /// About 190 dpi for an A4 page; long sides capped so each page stays light (Android's numbers).
  static let pdfRenderWidth: CGFloat = 1600
  static let pdfRenderMaxSide: CGFloat = 2400
  static let maxPdfPages = 300

  struct ImportedPage {
    var file: String
    var width: CGFloat
    var height: CGFloat
  }

  enum ImportError: Error {
    case message(String)
  }

  /// A PDF from her files, named after the file. Throws with a message she can read.
  @discardableResult
  func importPDF(_ url: URL) async throws -> NotebookMeta {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let doc = PDFDocument(url: url) else { throw ImportError.message(L("that_file_isn_t_a_pdf")) }
    if doc.isLocked { throw ImportError.message(L("this_pdf_is_password_protected_remove")) }
    let count = min(doc.pageCount, Self.maxPdfPages)
    if count == 0 { throw ImportError.message(L("that_pdf_has_no_pages")) }
    let images = AppFiles.folders.images
    let pdfId = newId()
    let kept = (try? FileManager.default.copyItem(at: url, to: images.appendingPathComponent("pdf-\(pdfId).pdf"))) != nil
    var pages: [ImportedPage] = []
    for i in 0..<count {
      guard let page = doc.page(at: i) else { continue }
      let box = page.bounds(for: .mediaBox)
      let turned = page.rotation % 180 != 0
      let w = turned ? box.height : box.width, h = turned ? box.width : box.height
      guard w > 0, h > 0 else { continue }
      let scale = min(Self.pdfRenderWidth / w, Self.pdfRenderMaxSide / max(w, h))
      let size = CGSize(width: max((w * scale).rounded(), 1), height: max((h * scale).rounded(), 1))
      let picture = page.thumbnail(of: size, for: .mediaBox)
      let name = kept ? PictureRow.pdfPageFile(pdf: pdfId, page: i, unique: newId()) : "\(newId()).jpg"
      guard let jpeg = Self.onWhite(picture).jpegData(compressionQuality: 0.88) else { continue }
      try? jpeg.write(to: images.appendingPathComponent(name))
      pages.append(ImportedPage(file: name, width: w, height: h))
      await Task.yield()
    }
    if pages.isEmpty { throw ImportError.message(L("that_pdf_has_no_pages")) }
    let title = url.deletingPathExtension().lastPathComponent
    return build(kind: .pdf, title: title.isEmpty ? "PDF" : title, pages: pages)
  }

  /// Pictures picked together: one item, a picture on each page (Android's `Imports.pictures`).
  @discardableResult
  func importPictures(_ urls: [URL]) async -> NotebookMeta? {
    var sources: [CGImageSource] = []
    for url in urls {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      if let src = CGImageSourceCreateWithURL(url as CFURL, nil) { sources.append(src) }
    }
    return await importPictures(sources)
  }

  /// Photos from the photo picker (their data), as one Picture item.
  @discardableResult
  func importPictures(data: [Data]) async -> NotebookMeta? {
    await importPictures(data.compactMap { CGImageSourceCreateWithData($0 as CFData, nil) })
  }

  private func importPictures(_ sources: [CGImageSource]) async -> NotebookMeta? {
    var pages: [ImportedPage] = []
    for src in sources {
      let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: Self.pdfRenderMaxSide,
        kCGImageSourceCreateThumbnailWithTransform: true,
      ]
      guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
        let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.9)
      else { continue }
      let name = "\(newId()).jpg"
      try? jpeg.write(to: AppFiles.folders.images.appendingPathComponent(name))
      pages.append(ImportedPage(file: name, width: CGFloat(cg.width), height: CGFloat(cg.height)))
      await Task.yield()
    }
    guard !pages.isEmpty else { return nil }
    return build(kind: .picture, title: pages.count > 1 ? English.nPictures(pages.count) : English.picture, pages: pages)
  }

  /// A transparent PDF page on white, as Android renders it.
  private static func onWhite(_ image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
      UIColor.white.setFill()
      ctx.fill(CGRect(origin: .zero, size: image.size))
      image.draw(at: .zero)
    }
  }

  /// The item itself: pages the shape of the first one, each picture filling its page (one of another
  /// shape sits in the middle), every picture a page of its own (`pdfPage`: the lasso never takes it).
  private func build(kind: DocKind, title: String, pages: [ImportedPage]) -> NotebookMeta {
    let folder: String? = if case .folder(let id) = shelf { id } else { nil }
    let first = pages[0]
    let aspect = Float(first.width / first.height)
    let layout = Pages.of(landscape: aspect > 1, aspect: aspect)
    let now = nowMillis()
    let taken = notebooks.filter { $0.folderId == folder }.map(\.title)
    let meta = NotebookMeta(
      id: newId(), title: Names.numbered(title, taken: taken), created: now, updated: now, cover: 0xFF7A_4ED6, paper: .BLANK,
      folderId: folder, pages: pages.count, landscape: layout.isLandscape, kind: kind, pageAspect: aspect)
    try? db.insert(meta)
    var placed: [(rect: CGRect, file: String)] = []
    for (i, p) in pages.enumerated() {
      let r = layout.rect(i)
      let s = min(CGFloat(r.width) / p.width, CGFloat(r.height) / p.height)
      let w = Float(p.width * s), h = Float(p.height * s)
      let c = r.center
      let rect = Rect(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2)
      try? db.put(PictureRow(id: newId(), z: Int64(i), file: p.file, rect: rect, pdfPage: true).itemRow, in: meta.id)
      placed.append((CGRect(rect), p.file))
    }
    // Its preview: the top of the first page, as the library shows notebooks.
    let layer = PagesLayer()
    layer.layout = layout
    layer.count = pages.count
    layer.paper = .BLANK
    if let pic = placed.first, let img = UIImage(contentsOfFile: AppFiles.folders.images.appendingPathComponent(pic.file).path)?.cgImage {
      layer.under.pictures = [(pic.rect, img)]
    }
    Thumbnail.save(id: meta.id, region: Thumbnail.previewRegion(CGRect(layout.rect(0))), pages: layer, drawing: PKDrawing(), db: db)
    reload()
    return meta
  }
}
