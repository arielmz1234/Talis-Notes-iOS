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
            lib.reload()
            withAnimation(.easeInOut(duration: 0.42)) { open = nil }
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
    .onAppear {
      let args = ProcessInfo.processInfo.arguments
      if args.contains("-openFirst"), let first = lib.shown.first { open = first }
    }
  }
}
