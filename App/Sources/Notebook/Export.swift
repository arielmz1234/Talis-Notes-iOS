import PencilKit
import SwiftUI
import TaliCore
import UniformTypeIdentifiers

/// PDF quality (Android's `PdfQuality`): how sharp pictures and slides are kept.
enum PdfQuality: CaseIterable {
  case best, balanced, light

  var name: String {
    switch self {
    case .best: L("pdf_quality_best")
    case .balanced: L("pdf_quality_balanced")
    case .light: L("pdf_quality_light")
    }
  }
  var detail: String {
    switch self {
    case .best: L("pdf_quality_best_detail")
    case .balanced: L("pdf_quality_balanced_detail")
    case .light: L("pdf_quality_light_detail")
    }
  }
  /// Pixels per world unit (1/160 inch) pictures are reduced to: 150 or 75 dpi; nil keeps them whole.
  var picturePixelsPerUnit: CGFloat? {
    switch self {
    case .best: nil
    case .balanced: 150 / 160
    case .light: 75 / 160
    }
  }
  /// Pixels per PDF point for the writing.
  var sharpness: CGFloat {
    switch self {
    case .best: 4
    case .balanced: 2.5
    case .light: 1.4
    }
  }
}

/// The export dialog's main choice (Android's `ExportChoice`): a quality, or one long page.
enum ExportChoice: CaseIterable {
  case best, balanced, light, long

  var quality: PdfQuality {
    switch self {
    case .best, .long: .best
    case .balanced: .balanced
    case .light: .light
    }
  }
  var label: String { self == .long ? L("one_long_page") : quality.name }
  var detail: String { self == .long ? L("everything_on_one_long_page_sized") : quality.detail }
}

/// Everything an export needs, read from the canvas on the main thread so the PDF can be made off it.
struct ExportSource: @unchecked Sendable {
  var rows: [ItemRow]
  var drawing: PKDrawing
  var layout: Pages
  /// Set for a paged notebook.
  var pageCount: Int?
  var paper: PaperSpec

  /// Whether imported slides sit on it (they can come back as their own pages).
  var hasPdfPages: Bool { rows.contains { PictureRow($0)?.pdfPage == true } }

  /// The PDF (Android's `Exporter.pdf`): pages cut by [layout], each exactly its size in points (A4 is
  /// 595 × 842), the paper, pictures at [quality]'s resolution (Best draws slides from the PDF itself),
  /// shapes, typed text as real text, then the writing.
  func pdf(_ layout: PdfLayout, _ quality: PdfQuality) -> Data {
    let drawn = rows.filter { $0.kind != MemoRow.kind }
    let items = drawn.map { ExportPages.Item(Rect($0.l, $0.t, $0.r, $0.b), pdfPage: PictureRow($0)?.pdfPage ?? false) }
    let rects = ExportPages.pages(layout, items: items, pages: self.layout, pageCount: pageCount, fixedGrid: UserDefaults.standard.bool(forKey: "pageGuides"))
    let layer = PagesLayer()
    layer.layout = self.layout
    layer.count = pageCount ?? 1
    layer.paper = paper
    layer.picture = paper.picture
    // A paged notebook's own pages carry their paper; anything else is painted as one sheet.
    let ownPages = pageCount != nil && layout == .a4Pages
    layer.drawsPaper = ownPages
    var under = UnderItems()
    for row in drawn {
      if let t = TextRow(row) {
        under.texts.append(t)
      } else if let s = ShapeRow(row) {
        under.shapes.append(s)
      } else if quality == .best, let sharp = SharpPage.of(row) {
        under.pdfPages.append(sharp)
      } else if let p = PictureRow(row), let image = pictureImage(p, pixelsPerUnit: quality.picturePixelsPerUnit) {
        under.pictures.append(PlacedPicture(row: p, image: image))
      }
    }
    layer.under = under
    let data = NSMutableData()
    UIGraphicsBeginPDFContextToData(data, .zero, nil)
    for r in rects {
      let pts = ExportPages.points(r)
      let size = CGSize(width: pts.width, height: pts.height)
      let world = CGRect(r)
      UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: size), nil)
      guard let cg = UIGraphicsGetCurrentContext() else { continue }
      cg.saveGState()
      let scale = size.width / world.width
      cg.scaleBy(x: scale, y: size.height / world.height)
      cg.translateBy(x: -world.minX, y: -world.minY)
      cg.clip(to: world)
      if !ownPages { PaperPainter.draw(paper, area: world, endless: pageCount == nil, in: cg, scale: scale, print: true, picture: layer.picture) }
      layer.paint(in: cg, scale: scale, print: true)
      cg.restoreGState()
      drawing.image(from: world, scale: size.width / world.width * quality.sharpness).draw(in: CGRect(origin: .zero, size: size))
    }
    UIGraphicsEndPDFContext()
    return data as Data
  }
}

extension NoteCanvas.Coordinator {
  var exportSource: ExportSource? {
    guard let canvas else { return nil }
    return ExportSource(
      rows: (try? parent.db.items(of: parent.notebook.id)) ?? [], drawing: canvas.drawing, layout: layout, pageCount: paged ? pageCount : nil,
      paper: parent.settings.paper)
  }
}

extension CanvasBridge {
  var exportSource: ExportSource? { coordinator?.exportSource }
  var title: String { coordinator?.parent.notebook.title ?? English.untitled }
}

/// A PDF for the system's save screen.
struct ExportedPDF: FileDocument {
  static var readableContentTypes: [UTType] { [.pdf] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Export PDF (Android's `ExportDialog`): Best, Balanced, Light or One long page (and, with slides
/// on an endless canvas, the slides' own pages or A4 pages), with the real size of the file that
/// choice makes, then Cancel, Save or Share.
struct ExportCard: View {
  var bridge: CanvasBridge
  var paged: Bool
  var onClose: () -> Void
  @Environment(\.tali) private var c
  @State private var source: ExportSource?
  @State private var pagesLayout = PdfLayout.a4Pages
  @State private var choice = ExportChoice.best
  @State private var made: [String: Data] = [:]
  @State private var saving: ExportedPDF?
  @State private var sharing: URL?

  private var pageLayouts: [PdfLayout] { source?.hasPdfPages == true && !paged ? [.pdfPages, .a4Pages] : [.a4Pages] }
  private var layout: PdfLayout { choice == .long ? .onePage : pagesLayout }
  private var key: String { "\(layout)-\(choice.quality)" }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(L("export_pdf")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 16)
      if pageLayouts.count > 1 && choice != .long {
        Segmented(options: pageLayouts, selected: $pagesLayout) { $0 == .pdfPages ? L("slides_own_pages") : L("a4_pages") }
        Spacer().frame(height: 14)
      }
      Segmented(options: ExportChoice.allCases, selected: $choice) { $0.label }
      Spacer().frame(height: 12)
      Text(made[key].map { sizeLabel($0.count) } ?? L("making_the_pdf_to_measure_it"))
        .font(TaliType.titleSmall).foregroundStyle(made[key] != nil ? c.ink : c.inkFaint)
        .accessibilityIdentifier("export-size")
      Spacer().frame(height: 2)
      Text(detail).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).lineLimit(3, reservesSpace: true)
      Spacer().frame(height: 24)
      HStack(spacing: 10) {
        Spacer()
        Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle())
        Button(L("save")) { if let d = made[key] { saving = ExportedPDF(data: d) } }.buttonStyle(QuietButtonStyle())
        Button(L("share")) { if let d = made[key] { sharing = write(d) } }.buttonStyle(PrimaryButtonStyle())
          .accessibilityIdentifier("export-share")
      }
    }
    .padding(28)
    .frame(maxWidth: 560)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
    .onAppear {
      source = bridge.exportSource
      if let first = pageLayouts.first { pagesLayout = first }
    }
    .task(id: key) {
      guard made[key] == nil, let source else { return }
      let (k, l, q) = (key, layout, choice.quality)
      let d = await Task.detached(priority: .userInitiated) { source.pdf(l, q) }.value
      made[k] = d
      if ProcessInfo.processInfo.arguments.contains("-uitest") { try? d.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("export-\(k).pdf")) }
    }
    .fileExporter(
      isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), document: saving, contentType: .pdf,
      defaultFilename: bridge.title
    ) { _ in onClose() }
    .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
      if let url = sharing { ShareSheet(items: [url]) }
    }
  }

  private var detail: String {
    if choice == .long { return choice.detail }
    if layout == .pdfPages { return L("each_slide_you_imported_comes_back") + choice.detail }
    return (paged ? L("every_page_of_the_notebook_as") : L("the_canvas_cut_into_a4_pages")) + choice.detail
  }

  private func write(_ d: Data) -> URL? {
    let name = bridge.title.replacingOccurrences(of: "/", with: "-")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
    return (try? d.write(to: url)) != nil ? url : nil
  }

  private func sizeLabel(_ bytes: Int) -> String {
    if bytes >= 1_000_000 { return String(format: L("file_size_1f_mb"), Double(bytes) / 1_000_000) }
    if bytes >= 1_000 { return L("file_size_n_kb", Int((Double(bytes) / 1_000).rounded())) }
    return L("file_size_under_1_kb")
  }
}

/// The system's share sheet.
struct ShareSheet: UIViewControllerRepresentable {
  var items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
  func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
