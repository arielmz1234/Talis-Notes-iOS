import SwiftUI
import TaliCore
import UniformTypeIdentifiers

/// Where the app keeps its files, as on Android: images/, thumbs/ and audio/ next to the database.
enum AppFiles {
  static var root: URL {
    let fm = FileManager.default
    let base = ProcessInfo.processInfo.arguments.contains("-uitest")
      ? fm.temporaryDirectory.appendingPathComponent("uitest-files")
      : fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? fm.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }

  static var folders: BackupArchive.Folders {
    let r = root
    let f = BackupArchive.Folders(
      images: r.appendingPathComponent("images"), thumbs: r.appendingPathComponent("thumbs"), audio: r.appendingPathComponent("audio"),
      work: FileManager.default.temporaryDirectory.appendingPathComponent("work"))
    for d in [f.images, f.thumbs, f.audio, f.work] { try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    return f
  }

  /// The settings a backup carries, in the Android app's `AppSettings` shape (keys it doesn't know
  /// are ignored there, and missing ones take their defaults).
  @MainActor static func settingsJSON() -> String {
    struct Out: Encodable {
      var pens: [PenSlot]
      var defaultPaper: String
    }
    let out = Out(pens: PenStore.load(), defaultPaper: UserDefaults.standard.string(forKey: "defaultPaper") ?? "GRID")
    return (try? String(data: JSONEncoder().encode(out), encoding: .utf8)) ?? "{}"
  }
}

/// A backup file as a document the system's save screen can write.
struct BackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.zip] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Backups: save everything into one file, or bring notebooks back from backup files (merging,
/// never deleting). iCloud and Google Drive come later (see PLAN.md).
struct BackupCard: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @Environment(\.dismiss) private var dismiss
  @State private var saving: BackupDocument?
  @State private var picking = false
  @State private var status: String?
  @State private var busy = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(L("backups")).font(TaliFont.heading(26)).foregroundStyle(c.ink)
        Spacer()
        Button(L("done")) { dismiss() }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("backups-done")
      }
      Text(L("every_stroke_is_saved_the_moment")).font(TaliFont.body(15)).foregroundStyle(c.inkMuted)
      VStack(alignment: .leading, spacing: 10) {
        Text(L("backup_file")).font(TaliFont.body(17, .semibold)).foregroundStyle(c.ink)
        Text(L("everything_in_one_file_notebooks_pictures")).font(TaliFont.body(14)).foregroundStyle(c.inkMuted)
        HStack(spacing: 10) {
          Button(L("save_backup_file")) { save() }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
          Button(L("restore_files")) { picking = true }.buttonStyle(QuietButtonStyle()).disabled(busy)
        }
        Text(L("restoring_never_deletes_anything_notebooks_from")).font(TaliFont.body(13)).foregroundStyle(c.inkFaint)
      }
      .padding(18)
      .background(RoundedRectangle(cornerRadius: 20).fill(c.sunken.opacity(0.6)))
      if let status {
        Text(status).font(TaliFont.body(15, .semibold)).foregroundStyle(c.accent).transition(.opacity)
      }
    }
    .padding(26)
    .frame(maxWidth: 600)
    .cloudSurface(radius: 28, crown: .edge)
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .presentationBackground(.clear)
    .fileExporter(
      isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), document: saving, contentType: .zip,
      defaultFilename: BackupArchive.fileName()
    ) { result in
      switch result {
      case .success: show(L("backup_saved"))
      case .failure(let e): show(L("couldn_t_save_the_backup") + ": " + e.localizedDescription)
      }
    }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.zip], allowsMultipleSelection: true) { result in
      guard case .success(let urls) = result else { return }
      restore(urls)
    }
  }

  private func show(_ s: String) { withAnimation(.easeOut(duration: 0.2)) { status = s } }

  private func save() {
    busy = true
    show(L("saving_backup"))
    let db = lib.db, settings = AppFiles.settingsJSON(), folders = AppFiles.folders
    Task {
      let result = await Task.detached { Result { try BackupArchive.write(db: db, settingsJSON: settings, folders: folders, now: nowMillis()) } }.value
      busy = false
      switch result {
      case .success(let d): saving = BackupDocument(data: d)
      case .failure(let e): show(L("couldn_t_save_the_backup") + ": " + "\(e)")
      }
    }
  }

  private func restore(_ urls: [URL]) {
    busy = true
    show(L("restoring"))
    let db = lib.db, folders = AppFiles.folders
    Task {
      let (summary, problem) = await Task.detached { () -> (MergeResult, Bool) in
        var total = MergeResult()
        var failed = false
        for url in urls {
          let open = url.startAccessingSecurityScopedResource()
          defer { if open { url.stopAccessingSecurityScopedResource() } }
          do {
            let (r, _) = try BackupArchive.restore(try Data(contentsOf: url), into: db, folders: folders)
            total.added += r.added
            total.updated += r.updated
            total.kept += r.kept
          } catch {
            failed = true
          }
        }
        return (total, failed)
      }.value
      busy = false
      lib.reload()
      var parts: [String] = []
      if summary.added > 0 { parts.append(summary.added == 1 ? L("t_1_notebook_added") : L("n_notebooks_added", summary.added)) }
      if summary.updated > 0 { parts.append(summary.updated == 1 ? L("t_1_notebook_updated") : L("n_notebooks_updated", summary.updated)) }
      if parts.isEmpty { parts.append(problem ? L("couldn_t_open_the_file") : L("everything_in_the_backup_was_already")) }
      show(parts.joined(separator: ", "))
    }
  }
}
