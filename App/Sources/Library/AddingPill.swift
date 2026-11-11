import Observation
import SwiftUI
import TaliCore

/// What the library's + is adding (Android's `LibraryViewModel.Adding`): words, whether it's still
/// going or went wrong, and what was made (for "Added …" and Open). One job at a time.
@MainActor @Observable
final class AddingModel {
  struct State: Equatable {
    var words: String
    var busy: Bool
    var failed = false
    var added: String?
  }

  private(set) var state: State?
  @ObservationIgnored private var job: Task<Void, Never>?

  func dismiss() { state = nil }

  /// Files picked with + › File: each PDF an item of its own, pictures picked together one Picture item.
  func addFiles(_ urls: [URL], into lib: Library) {
    let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
    let pictures = urls.filter { $0.pathExtension.lowercased() != "pdf" }
    run {
      var last: NotebookMeta?
      for url in pdfs {
        let name = url.deletingPathExtension().lastPathComponent
        self.state = State(words: L("adding_n", name), busy: true)
        do {
          last = try await lib.importPDF(url) { done, total in self.state = State(words: L("adding_n_page_n_of_n", name, done, total), busy: true) }
        } catch Library.ImportError.message(let m) {
          self.state = State(words: m, busy: false, failed: true)
          if pdfs.count == 1 && pictures.isEmpty { return nil }
        } catch {
          self.state = State(words: L("couldn_t_open_that_file"), busy: false, failed: true)
        }
      }
      if !pictures.isEmpty {
        self.state = State(words: L("adding_pictures"), busy: true)
        last = await lib.importPictures(pictures) ?? last
      }
      return last
    }
  }

  /// Photos from + › Photo or the camera: one Picture item, a picture on each page.
  func addPhotos(_ data: [Data], into lib: Library) {
    guard !data.isEmpty else { return }
    run {
      self.state = State(words: L("adding_pictures"), busy: true)
      return await lib.importPictures(data: data)
    }
  }

  private func run(_ block: @escaping @MainActor () async -> NotebookMeta?) {
    guard job == nil else { return }
    job = Task {
      let made = await block()
      if let made {
        state = State(words: L("added_n", made.title), busy: false, added: made.id)
      } else if state?.busy == true {
        state = State(words: L("that_didn_t_work_try_again"), busy: false, failed: true)
      }
      job = nil
      let shown = state
      try? await Task.sleep(for: .seconds(shown?.added != nil ? 9 : 6))
      if state == shown { withAnimation(.easeOut(duration: 0.16)) { state = nil } }
    }
  }
}

/// The pill at the bottom of the library while something is added: progress, then "Added …" with
/// Open, or what went wrong (Android's `AddingPill`).
struct AddingPill: View {
  var adding: AddingModel
  var onOpen: (String) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    ZStack {
      if let a = adding.state {
        HStack(spacing: 0) {
          Image(systemName: a.failed ? "exclamationmark.circle" : (a.busy ? "arrow.down.circle" : "checkmark.circle"))
            .font(.system(size: 18)).foregroundStyle(a.failed ? c.danger : c.accent)
          Spacer().frame(width: 10)
          Text(a.words).font(TaliType.labelLarge).foregroundStyle(a.failed ? c.danger : c.ink).lineLimit(2)
            .accessibilityIdentifier("adding-words")
          Spacer().frame(width: 8)
          if let id = a.added {
            Button(L("open")) {
              adding.dismiss()
              onOpen(id)
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityIdentifier("adding-open")
          } else if !a.busy {
            Button { withAnimation(.easeOut(duration: 0.16)) { adding.dismiss() } } label: {
              Image(systemName: "xmark").font(.system(size: 15)).foregroundStyle(c.inkMuted).frame(width: 36, height: 36)
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .accessibilityLabel(L("close"))
          } else {
            Spacer().frame(width: 8)
          }
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
        .frame(minHeight: 40)
        .cloudSurface(radius: 20)
        .frame(maxWidth: 560)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 24)).animation(Ease.outStrong(duration: 0.26)), removal: .opacity.animation(.easeOut(duration: 0.16))))
      }
    }
    .animation(.easeOut(duration: 0.16), value: adding.state)
    .padding(.horizontal, 16)
    .padding(.bottom, 24)
  }
}
