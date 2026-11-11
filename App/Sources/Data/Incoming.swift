import Observation
import SwiftUI
import TaliCore
import UniformTypeIdentifiers

/// PDFs and pictures opened with Tali's Notes from another app (Android's `Incoming` and
/// `MainNavigation`): each opens as itself, a PDF item or a Picture item on its own pages, never into
/// a notebook. Until she saves it it's a draft, just for looking, unless *Add them to my notebooks* is
/// on. Backups opened this way are left alone here.
@MainActor @Observable
final class Incoming {
  /// What's happening while the item is made ("Opening the PDF…", "Adding pages… 3 of 12").
  private(set) var opening: String?

  /// Settings › PDFs from other apps › Add them to my notebooks (off: they open as drafts).
  static var toLibrary: Bool { UserDefaults.standard.bool(forKey: "pdfsToLibrary") }

  func open(_ url: URL, into lib: Library, then show: @escaping (NotebookMeta) -> Void) {
    let type = UTType(filenameExtension: url.pathExtension.lowercased())
    let isPDF = type?.conforms(to: .pdf) == true
    guard isPDF || type?.conforms(to: .image) == true else { return }
    let draft = !Self.toLibrary
    Task {
      defer {
        opening = nil
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
      }
      if isPDF {
        opening = L("opening_pdf")
        if let n = try? await lib.importPDF(url, draft: draft, progress: { done, total in self.opening = L("adding_pages_n_of_n", done, total) }) { show(n) }
      } else {
        opening = L("adding_pictures")
        if let n = await lib.importPictures([url], draft: draft) { show(n) }
      }
    }
  }
}

extension Library {
  /// A draft saved as one of hers: named (kept apart from names in that folder) and into the library.
  func saveDraft(_ id: String, title: String, folder: String?) -> String {
    let taken = notebooks.filter { $0.folderId == folder && $0.id != id }.map(\.title)
    let name = Names.numbered(title, taken: taken)
    try? db.run("UPDATE notebooks SET draft=0, title=?, folder_id=?, updated=? WHERE id=?", [.text(name), folder.map(NotesDb.Value.text) ?? .null, .int(nowMillis()), .text(id)])
    reload()
    return name
  }

  /// A draft left without saving goes, with its pictures and its PDF.
  func discardDraft(_ id: String) {
    let rows = (try? db.items(of: id)) ?? []
    let files = rows.compactMap(PictureRow.init).map(\.file)
    let pdfs = Set(files.compactMap { PictureRow.pdfSource(of: $0)?.pdf })
    try? db.erase(id)
    let images = AppFiles.folders.images
    for f in files { try? FileManager.default.removeItem(at: images.appendingPathComponent(f)) }
    for p in pdfs { try? FileManager.default.removeItem(at: images.appendingPathComponent("pdf-\(p).pdf")) }
    try? FileManager.default.removeItem(at: AppFiles.folders.thumbs.appendingPathComponent("\(id).png"))
  }

  /// Drafts left behind (the app closed while she was looking) wait a day, then go (Android's `sweepDrafts`).
  func sweepDrafts() {
    let dayAgo = nowMillis() - 24 * 3600 * 1000
    for n in (try? db.notebooks(where: "draft=1 AND created < ?", [.int(dayAgo)])) ?? [] { discardDraft(n.id) }
  }
}

/// While a PDF or pictures from another app are being made into an item: what's happening.
struct OpeningPill: View {
  var text: String?
  @Environment(\.tali) private var c

  var body: some View {
    ZStack {
      if let text {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small).tint(c.accent)
          Text(text).font(TaliType.labelLarge).foregroundStyle(c.ink)
        }
        .padding(.horizontal, 18).frame(height: 48)
        .cloudSurface(radius: 20)
        .transition(.opacity.combined(with: .offset(y: 16)))
      }
    }
    .animation(Ease.outStrong(duration: 0.26), value: text)
    .padding(.bottom, 24)
  }
}
