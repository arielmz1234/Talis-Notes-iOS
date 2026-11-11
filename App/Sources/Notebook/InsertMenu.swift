import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// What Insert adds to the page (Android's toolbar Insert menu).
enum InsertChoice { case picture, photo, pdf }

/// The toolbar's Insert: a picture, a photo from the camera, or PDF pages. A native menu on iOS, with
/// Android's rows (icon, name, a line under it).
struct InsertButton: View {
  var onPick: (InsertChoice) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Menu {
      row(.picture, "photo", L("picture"), L("from_your_photos_or_files"))
      if CameraScreen.available || ProcessInfo.processInfo.arguments.contains("-cameraPicture") {
        row(.photo, "camera", L("take_a_photo"), L("the_board_a_textbook_page_a"))
      }
      row(.pdf, "doc.richtext", L("pdf_pages"), L("lecture_slides_or_a_problem_sheet"))
    } label: {
      Image(systemName: "photo.badge.plus").font(.system(size: 19)).foregroundStyle(c.ink).frame(width: 44, height: 44)
    }
    .accessibilityLabel(L("insert"))
    .accessibilityIdentifier("tool-insert")
  }

  private func row(_ choice: InsertChoice, _ icon: String, _ title: String, _ detail: String) -> some View {
    Button { onPick(choice) } label: {
      Label(title, systemImage: icon)
      Text(detail)
    }
    .accessibilityIdentifier("insert-\(choice)")
  }
}

/// Runs Insert's choice: the photo picker, the camera or the file picker, then puts what came on the
/// page, with progress and the outcome in the hint line (Android's `NotebookContent` launchers).
struct InsertFlow: ViewModifier {
  @Binding var request: InsertChoice?
  var bridge: CanvasBridge
  var crop: CropModel
  var hint: (String) -> Void
  @Environment(Library.self) private var lib
  @State private var photo: PhotosPickerItem?

  func body(content: Content) -> some View {
    content
      .photosPicker(isPresented: shows(.picture), selection: $photo, matching: .images)
      .onChange(of: photo) { _, item in
        guard let item else { return }
        photo = nil
        Task { @MainActor in
          let data = try? await item.loadTransferable(type: Data.self)
          guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil), let page = Library.savePicture(src) else {
            hint(L("that_image_couldn_t_be_opened"))
            return
          }
          crop.offer(bridge.coordinator?.insertPicture(page))
        }
      }
      .fullScreenCover(isPresented: shows(.photo)) {
        CameraScreen(onClose: { request = nil }) { photos in
          request = nil
          for data in photos {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil), let page = Library.savePicture(src) else {
              hint(L("that_photo_couldn_t_be_opened"))
              continue
            }
            crop.offer(bridge.coordinator?.insertPicture(page))
          }
        }
      }
      .fileImporter(isPresented: shows(.pdf), allowedContentTypes: [.pdf]) { result in
        guard case .success(let url) = result else { return }
        Task { @MainActor in await addPDF(url) }
      }
      .onChange(of: request) { _, c in if Self.fake, let c, c != .photo { fakePick(c) } }
  }

  /// Under UI tests with -fakePickers, the seeded PDF and a drawn picture stand in for what she'd pick.
  private static let fake = ProcessInfo.processInfo.arguments.contains("-fakePickers")

  private func shows(_ c: InsertChoice) -> Binding<Bool> {
    Binding(
      get: { request == c && !(Self.fake && c != .photo) },
      set: { if !$0, request == c { request = nil } })
  }

  @MainActor private func fakePick(_ c: InsertChoice) {
    request = nil
    switch c {
    case .pdf: Task { await addPDF(FileManager.default.temporaryDirectory.appendingPathComponent("Lecture slides.pdf")) }
    case .picture:
      let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { ctx in
        UIColor(red: 0.98, green: 0.9, blue: 0.75, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        UIColor.systemOrange.setFill()
        ctx.cgContext.fillEllipse(in: CGRect(x: 420, y: 220, width: 360, height: 360))
      }
      if let data = image.jpegData(compressionQuality: 0.9), let src = CGImageSourceCreateWithData(data as CFData, nil), let page = Library.savePicture(src) {
        crop.offer(bridge.coordinator?.insertPicture(page))
      }
    case .photo: break
    }
  }

  @MainActor private func addPDF(_ url: URL) async {
    do {
      hint(L("opening_pdf"))
      let pages = try await lib.renderPDF(url) { done, total in hint(L("adding_pages_n_of_n", done, total)) }
      bridge.coordinator?.insertPages(pages)
      hint(pages.count == 1 ? L("added_1_page_write_right_on") : L("added_n_pages_write_right_on", pages.count))
    } catch Library.ImportError.message(let m) {
      hint(m)
    } catch {
      hint(L("couldn_t_read_that_pdf"))
    }
  }
}

/// Pictures, PDFs and text dragged over from an app side by side (Android's `onDropped`): pictures
/// land centred where they're dropped, PDFs as pages, text as a text box. Nothing lands while she's
/// just looking.
struct DropOnPage: ViewModifier {
  var enabled: Bool
  var bridge: CanvasBridge
  var crop: CropModel
  var hint: (String) -> Void
  @Environment(Library.self) private var lib

  func body(content: Content) -> some View {
    content
      .onDrop(of: [.pdf, .image, .plainText], isTargeted: nil) { providers, location in
        guard enabled else { return false }
        Task { @MainActor in await take(providers, at: location) }
        return true
      }
      .task {
        guard ProcessInfo.processInfo.arguments.contains("-fakeDrop") else { return }
        try? await Task.sleep(for: .seconds(2))
        let picture = PageImaging.samplePhoto().scaled(maxSide: 900)
        await take([NSItemProvider(object: picture)], at: CGPoint(x: 260, y: 360))
        await take([NSItemProvider(object: "Dropped from another app" as NSString)], at: CGPoint(x: 560, y: 640))
      }
  }

  @MainActor private func take(_ providers: [NSItemProvider], at location: CGPoint) async {
    guard let c = bridge.coordinator else { return }
    let at = c.contentPoint(location)
    var index = 0
    for p in providers {
      if p.hasItemConformingToTypeIdentifier(UTType.pdf.identifier), let url = await file(p, .pdf) {
        do {
          let pages = try await lib.renderPDF(url) { done, total in hint(L("adding_pages_n_of_n", done, total)) }
          c.insertPages(pages)
          hint(pages.count == 1 ? L("added_1_page_write_right_on") : L("added_n_pages_write_right_on", pages.count))
        } catch Library.ImportError.message(let m) {
          hint(m)
        } catch {
          hint(L("couldn_t_read_that_pdf"))
        }
      } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        guard let data = await data(p, .image), let src = CGImageSourceCreateWithData(data as CFData, nil), let page = Library.savePicture(src) else {
          hint(L("that_picture_couldn_t_be_opened_2"))
          continue
        }
        crop.offer(c.insertPicture(page, at: at, index: index))
        index += 1
      } else if p.canLoadObject(ofClass: NSString.self), let text = await string(p) {
        c.insertText(text, at: at)
      }
    }
  }

  private func data(_ p: NSItemProvider, _ type: UTType) async -> Data? {
    await withCheckedContinuation { done in _ = p.loadDataRepresentation(for: type) { d, _ in done.resume(returning: d) } }
  }

  private func string(_ p: NSItemProvider) async -> String? {
    await withCheckedContinuation { done in _ = p.loadObject(ofClass: NSString.self) { s, _ in done.resume(returning: (s as? NSString).map(String.init)) } }
  }

  /// The dropped file copied somewhere it stays while it's read.
  private func file(_ p: NSItemProvider, _ type: UTType) async -> URL? {
    await withCheckedContinuation { done in
      _ = p.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
        guard let url else { return done.resume(returning: nil) }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)-\(url.lastPathComponent)")
        done.resume(returning: (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? copy : nil)
      }
    }
  }
}
