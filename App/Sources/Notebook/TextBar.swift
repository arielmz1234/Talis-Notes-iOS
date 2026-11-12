import SwiftUI

/// The small bar above the text box being typed in (the bar of Android's `TextEditorOverlay`): the
/// text smaller or bigger, her first colours, the bin and done. It sits just above the box, or
/// below the toolbars when the box is near the top; on a narrow screen it keeps inside the edges
/// and shows as many colours as fit.
struct TextBarLayer: View {
  var info: TextBarInfo
  /// How far down the toolbars reach (in the layer's own coordinates).
  var topLimit: CGFloat
  var onSize: (Bool) -> Void
  var onColour: (UInt32) -> Void
  var onDelete: () -> Void
  var onDone: () -> Void
  @State private var width: CGFloat = 0

  private static let gap: CGFloat = 8

  var body: some View {
    GeometryReader { geo in
      let origin = geo.frame(in: .global).origin
      let x = min(max(info.corner.x - origin.x, Self.gap), max(geo.size.width - width - Self.gap, Self.gap))
      let y = max(info.corner.y - origin.y - 60, topLimit)
      ViewThatFits(in: .horizontal) {
        ForEach([6, 5, 4, 3, 2, 1, 0], id: \.self) { n in
          TextBar(color: info.color, colours: Array(Palettes.shared.saved.prefix(n)), onSize: onSize, onColour: onColour, onDelete: onDelete, onDone: onDone)
        }
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .frame(width: max(geo.size.width - 2 * Self.gap, 0), alignment: .leading)
      .offset(x: x, y: y)
    }
  }
}

private struct TextBar: View {
  var color: UInt32
  var colours: [UInt32]
  var onSize: (Bool) -> Void
  var onColour: (UInt32) -> Void
  var onDelete: () -> Void
  var onDone: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    FloatingBar(crown: .none, height: 48) {
      sizeButton("A−", grow: false)
      sizeButton("A+", grow: true)
      if !colours.isEmpty {
        divider
        ForEach(Array(colours.enumerated()), id: \.offset) { i, col in
          ColorDot(color: Color(argb: col), selected: col | 0xFF00_0000 == color | 0xFF00_0000, size: 24) { onColour(col) }
            .accessibilityLabel(L("colour"))
            .accessibilityIdentifier("text-colour-\(i)")
        }
      }
      divider
      ToolIcon(system: "trash", label: L("delete_text"), action: onDelete).accessibilityIdentifier("text-delete")
      ToolIcon(system: "checkmark", label: L("done"), action: onDone).accessibilityIdentifier("text-done")
    }
    .fixedSize()
  }

  private var divider: some View { Rectangle().fill(c.line).frame(width: 1, height: 24).padding(.horizontal, 6) }

  private func sizeButton(_ label: String, grow: Bool) -> some View {
    Button { onSize(grow) } label: {
      Text(label).font(TaliType.labelLarge).foregroundStyle(c.ink).frame(width: 40, height: 40).contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(grow ? L("bigger_text") : L("smaller_text"))
    .accessibilityIdentifier(grow ? "text-bigger" : "text-smaller")
  }
}
