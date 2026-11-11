import SwiftUI
import TaliCore

extension NoteCanvas.Coordinator {
  /// Whether writing or shapes are picked up (text alone can't be saved as a shape).
  var hasDrawingPicked: Bool { !lasso.picked.isEmpty || !lasso.pickedShapes.isEmpty }

  /// What's picked up as one shape to save (Android's `selectionGeometry`): clean shapes keep their
  /// exact geometry, writing becomes smooth lines; nil when there's nothing usable.
  func selectionGeometry() -> ShapeGeometry? {
    let strokes = stored.map(\.stroke).filter { lasso.picked.contains($0.id) }
    let picked = pickedShapeRows
    let parts = (strokes.map { (z: $0.z, part: CustomShape.Part.ink($0.inputs.points.map { Pt($0.x, $0.y) })) } + picked.map { (z: $0.z, part: .shape($0.geometry)) })
      .sorted { $0.z < $1.z }
    let boxes = strokes.map(\.bounds) + picked.compactMap { $0.geometry.bounds($0.size) }
      + texts.filter { lasso.pickedTexts.contains($0.id) }.map { t in
        let f = TextLook.frame(t)
        return Rect(Float(f.minX), Float(f.minY), Float(f.maxX), Float(f.maxY))
      }
    let bounds = boxes.dropFirst().reduce(boxes.first) { all, r in all.map { Rect(min($0.left, r.left), min($0.top, r.top), max($0.right, r.right), max($0.bottom, r.bottom)) } }
    return CustomShape.geometryFrom(parts.map(\.part), bounds: bounds)
  }
}

/// Names a selection before it joins My shapes, with a preview of the clean shape (Android's `SaveShapeDialog`).
struct SaveShapeCard: View {
  var geometry: ShapeGeometry
  var onClose: () -> Void
  var onSave: (String) -> Void
  @Environment(\.tali) private var c
  @State private var name = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 18) {
        GeometryIcon(geometry: geometry, color: c.blue, size: 72)
          .frame(width: 88, height: 88)
          .background(RoundedRectangle(cornerRadius: 20).fill(c.blueSoft))
        VStack(alignment: .leading, spacing: 4) {
          Text(L("save_as_shape")).font(TaliType.titleLarge).foregroundStyle(c.ink)
          Text(L("it_will_appear_in_shapes_under")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer().frame(height: 18)
      TextField("", text: $name, prompt: Text(L("name_e_g_i_beam")).foregroundStyle(c.inkFaint))
        .font(TaliType.bodyLarge).foregroundStyle(c.ink).tint(c.accent)
        .focused($focused).submitLabel(.done).onSubmit { onSave(name) }
        .padding(.horizontal, 16).frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 14).fill(c.background))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line, lineWidth: 1))
        .accessibilityLabel(L("shape_name"))
        .accessibilityIdentifier("shape-name")
      Spacer().frame(height: 24)
      HStack(spacing: 10) {
        Spacer()
        Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle())
        Button(L("save_shape")) { onSave(name) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("save-shape")
      }
    }
    .padding(28)
    .frame(maxWidth: 480)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
    .onAppear { focused = true }
  }
}
