import SwiftUI
import TaliCore

@main
struct TalisNotesApp: App {
  @State private var library = Library.open()
  @AppStorage("themeMode") private var themeMode = "LIGHT"

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(library)
        .taliTheme()
        .preferredColorScheme(scheme)
    }
  }

  /// The app starts in Light, as on Android; System default follows the device.
  private var scheme: ColorScheme? {
    let args = ProcessInfo.processInfo.arguments
    if args.contains("-dark") { return .dark }
    if args.contains("-light") { return .light }
    switch themeMode {
    case "DARK": return .dark
    case "SYSTEM": return nil
    default: return .light
    }
  }
}

struct RootView: View {
  @Environment(Library.self) private var lib
  @State private var open: NotebookMeta?
  @State private var incoming = Incoming()

  var body: some View {
    ZStack {
      LibraryView { n in
        lib.noteOpened(n.id)
        withAnimation(.easeInOut(duration: 0.42)) { open = n }
      }
      if let n = open {
        // A notebook never mirrors in Hebrew or Arabic: only its words change.
        NotebookView(
          notebook: n,
          onBack: {
            // Back on the shelf, the notebook shows its new paper, name and edit time.
            withAnimation(.easeInOut(duration: 0.42)) { open = nil }
            // After the canvas has saved its last changes as it closes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { lib.reload() }
          },
          onSwitch: { next in
            lib.noteOpened(next.id)
            withAnimation(.easeInOut(duration: 0.3)) { open = next }
          }
        )
        .id(n.id)
        .environment(\.layoutDirection, .leftToRight)
          .transition(.opacity)
          .zIndex(1)
      }
    }
    .overlay(alignment: .bottom) { OpeningPill(text: incoming.opening) }
    .onOpenURL { url in
      incoming.open(url, into: lib) { n in
        lib.noteOpened(n.id)
        withAnimation(.easeInOut(duration: 0.42)) { open = n }
      }
    }
    .onAppear {
      lib.sweepDrafts()
      let args = ProcessInfo.processInfo.arguments
      if args.contains("-openFirst"), let first = lib.shown.first { open = first }
      if let i = args.firstIndex(of: "-openURL"), i + 1 < args.count {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(args[i + 1])
        incoming.open(url, into: lib) { n in open = n }
      }
    }
  }
}
