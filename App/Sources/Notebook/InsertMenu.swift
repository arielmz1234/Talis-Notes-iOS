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
      if CameraPicker.available || ProcessInfo.processInfo.arguments.contains("-uitest") {
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
          bridge.coordinator?.insertPicture(page)
        }
      }
      .fullScreenCover(isPresented: shows(.photo)) {
        CameraPicker(
          onPhoto: { image in
            let upright = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
            guard let data = upright.jpegData(compressionQuality: 0.9), let src = CGImageSourceCreateWithData(data as CFData, nil),
              let page = Library.savePicture(src)
            else {
              hint(L("that_photo_couldn_t_be_opened"))
              return
            }
            bridge.coordinator?.insertPicture(page)
          },
          onClose: { request = nil }
        )
        .ignoresSafeArea()
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
        bridge.coordinator?.insertPicture(page)
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
