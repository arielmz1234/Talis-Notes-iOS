import PencilKit
import SwiftUI
import TaliCore
import UniformTypeIdentifiers

/// PDF quality (Android's `PdfQuality`), as how sharp the writing and pictures are drawn.
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
  /// Pixels per PDF point for the writing.
  var sharpness: CGFloat {
    switch self {
    case .best: 4
    case .balanced: 2.5
    case .light: 1.4
    }
  }
}

extension NoteCanvas.Coordinator {
  /// The notebook as an A4 PDF (Android's `Exporter.pdf`): every page of a paged notebook; an
  /// endless canvas cut into A4 pages, empty ones skipped.
  func makePDF(_ quality: PdfQuality) -> Data? {
    guard let canvas, let pages else { return nil }
    let drawing = canvas.drawing
    var rects: [CGRect] = []
    if paged {
      rects = (0..<pageCount).map { CGRect(layout.rect($0)) }
    } else {
      let w = CGFloat(Pages.portrait.width), h = CGFloat(Pages.portrait.height)
      let content = drawing.bounds
      if content.isNull || content.isEmpty {
        rects = [CGRect(x: 0, y: 0, width: w, height: h)]
      } else {
        for row in Int(floor(content.minY / h))...Int(floor(content.maxY / h)) {
          for col in Int(floor(content.minX / w))...Int(floor(content.maxX / w)) {
            let r = CGRect(x: CGFloat(col) * w, y: CGFloat(row) * h, width: w, height: h)
            if drawing.strokes.contains(where: { $0.renderBounds.intersects(r) }) { rects.append(r) }
          }
        }
      }
    }
    // A4 in points: 595 × 842 (or on its side).
    let ptPerUnit: CGFloat = 72 / 160
    let data = NSMutableData()
    UIGraphicsBeginPDFContextToData(data, .zero, nil)
    for r in rects {
      let size = CGSize(width: r.width * ptPerUnit, height: r.height * ptPerUnit)
      UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: size), nil)
      guard let cg = UIGraphicsGetCurrentContext() else { continue }
      cg.saveGState()
      cg.scaleBy(x: ptPerUnit, y: ptPerUnit)
      cg.translateBy(x: -r.minX, y: -r.minY)
      cg.clip(to: r)
      pages.pages.draw(in: cg)
      cg.restoreGState()
      drawing.image(from: r, scale: ptPerUnit * quality.sharpness).draw(in: CGRect(origin: .zero, size: size))
    }
    UIGraphicsEndPDFContext()
    return data as Data
  }
}

extension CanvasBridge {
  func pdf(_ q: PdfQuality) -> Data? { coordinator?.makePDF(q) }
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

/// Export PDF (Android's `ExportDialog`): Best, Balanced or Light, with the real size of the file
/// that choice makes, then Cancel, Save or Share.
struct ExportCard: View {
  var bridge: CanvasBridge
  var paged: Bool
  var onClose: () -> Void
  @Environment(\.tali) private var c
  @State private var quality = PdfQuality.best
  @State private var made: [PdfQuality: Data] = [:]
  @State private var saving: ExportedPDF?
  @State private var sharing: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(L("export_pdf")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 16)
      Segmented(options: PdfQuality.allCases, selected: $quality) { $0.name }
      Spacer().frame(height: 12)
      Text(made[quality].map { sizeLabel($0.count) } ?? L("making_the_pdf_to_measure_it"))
        .font(TaliType.titleSmall).foregroundStyle(made[quality] != nil ? c.ink : c.inkFaint)
      Spacer().frame(height: 2)
      Text((paged ? L("every_page_of_the_notebook_as") : L("the_canvas_cut_into_a4_pages")) + quality.detail)
        .font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).lineLimit(3, reservesSpace: true)
      Spacer().frame(height: 24)
      HStack(spacing: 10) {
        Spacer()
        Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle())
        Button(L("save")) { if let d = made[quality] { saving = ExportedPDF(data: d) } }.buttonStyle(QuietButtonStyle())
        Button(L("share")) { if let d = made[quality] { sharing = write(d) } }.buttonStyle(PrimaryButtonStyle())
      }
    }
    .padding(28)
    .frame(maxWidth: 560)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
    .task(id: quality) {
      if made[quality] == nil, let d = bridge.pdf(quality) { made[quality] = d }
    }
    .fileExporter(
      isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), document: saving, contentType: .pdf,
      defaultFilename: bridge.title
    ) { _ in onClose() }
    .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
      if let url = sharing { ShareSheet(items: [url]) }
    }
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
