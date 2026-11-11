import Observation
import SwiftUI
import TaliCore

/// Cropping a picture in place (Android's `startCrop` … `finishCrop`): the whole picture shows round
/// a frame with marks at its corners and sides, the part outside shaded; Reset, Cancel and Done float
/// at the bottom; a touch off the picture keeps the crop. The whole picture is kept, so a crop can be
/// opened up again later.
@MainActor @Observable
final class CropModel {
  /// A picture just added: Crop is offered beside it, as Android's menu offers it first.
  private(set) var offered: PictureRow?
  private(set) var edit: CropEdit?
  private(set) var dragging = false
  private(set) var image: UIImage?
  /// Screen points per world unit and the screen point of the world's origin.
  private(set) var zoom: CGFloat = 1
  private(set) var origin: CGPoint = .zero

  @ObservationIgnored weak var bridge: CanvasBridge?
  @ObservationIgnored private var grab = -1
  @ObservationIgnored private var from = Rect(0, 0, 0, 0)

  func offer(_ p: PictureRow?) {
    guard let p, CropEdit.croppable(p) else { return }
    offered = p
  }

  func dismissOffer() { offered = nil }

  func cameraMoved() {
    guard let canvas = bridge?.coordinator?.canvas else { return }
    zoom = canvas.zoomScale
    origin = CGPoint(x: -canvas.contentOffset.x, y: -canvas.contentOffset.y)
  }

  func screen(_ r: Rect) -> CGRect {
    CGRect(x: CGFloat(r.left) * zoom + origin.x, y: CGFloat(r.top) * zoom + origin.y, width: CGFloat(r.width) * zoom, height: CGFloat(r.height) * zoom)
  }

  func start() {
    guard let p = offered.flatMap({ bridge?.coordinator?.storedPicture($0.id) }) ?? offered else { return }
    offered = nil
    cameraMoved()
    var whole = p
    whole.crop = nil
    image = pictureImage(whole, pixelsPerUnit: 2, cap: 2400).map { UIImage(cgImage: $0) }
    edit = CropEdit(p)
  }

  func reset() { edit?.frame = edit?.whole ?? Rect(0, 0, 0, 0) }

  func finish(keep: Bool) {
    guard let e = edit else { return }
    edit = nil
    dragging = false
    image = nil
    let done = e.finished
    if keep, done.rect != e.picture.rect || done.crop != e.picture.crop { bridge?.coordinator?.replacePicture(e.picture, with: done) }
  }

  /// A touch at [p] (screen): a handle or the frame is picked up, off the picture the crop is kept.
  func touchDown(_ p: CGPoint) {
    guard let e = edit else { return }
    let f = screen(e.frame)
    let handles = CropEdit.handles(e.frame).map { CGPoint(x: CGFloat($0.x) * zoom + origin.x, y: CGFloat($0.y) * zoom + origin.y) }
    let near = handles.indices.min { hypot(handles[$0].x - p.x, handles[$0].y - p.y) < hypot(handles[$1].x - p.x, handles[$1].y - p.y) }!
    if hypot(handles[near].x - p.x, handles[near].y - p.y) < 28 {
      grab = near
    } else if f.contains(p) {
      grab = 8
    } else {
      grab = -1
      if !screen(e.whole).contains(p) { finish(keep: true) }
      return
    }
    from = e.frame
    dragging = true
  }

  func drag(_ translation: CGSize) {
    guard grab >= 0, let e = edit else { return }
    edit?.frame = e.dragged(grab, from: from, dx: Float(translation.width / zoom), dy: Float(translation.height / zoom), zoom: Float(zoom))
  }

  func lift() {
    grab = -1
    dragging = false
  }
}

/// The picture being cropped, over the page.
struct CropLayer: View {
  var crop: CropModel
  @Environment(\.tali) private var c

  var body: some View {
    if let e = crop.edit {
      let whole = crop.screen(e.whole), f = crop.screen(e.frame)
      ZStack(alignment: .topLeading) {
        if let image = crop.image {
          Image(uiImage: image).resizable().frame(width: whole.width, height: whole.height).offset(x: whole.minX, y: whole.minY)
        }
        Canvas { ctx, _ in
          var shade = Path(whole)
          shade.addRect(f)
          ctx.fill(shade, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
          ctx.stroke(Path(f), with: .color(.white.opacity(0.9)), lineWidth: 1.2)
          if crop.dragging {
            var thirds = Path()
            for i in 1...2 {
              let x = f.minX + f.width * CGFloat(i) / 3, y = f.minY + f.height * CGFloat(i) / 3
              thirds.move(to: CGPoint(x: x, y: f.minY))
              thirds.addLine(to: CGPoint(x: x, y: f.maxY))
              thirds.move(to: CGPoint(x: f.minX, y: y))
              thirds.addLine(to: CGPoint(x: f.maxX, y: y))
            }
            ctx.stroke(thirds, with: .color(.white.opacity(0.5)), lineWidth: 1)
          }
          let len = min(18, min(f.width, f.height) / 3), i: CGFloat = 1.5
          let l = f.minX + i, t = f.minY + i, r = f.maxX - i, b = f.maxY - i
          var marks = Path()
          for (a, z) in [
            ((l, t), (l + len, t)), ((l, t), (l, t + len)), ((r, t), (r - len, t)), ((r, t), (r, t + len)), ((r, b), (r - len, b)), ((r, b), (r, b - len)),
            ((l, b), (l + len, b)), ((l, b), (l, b - len)), ((f.midX - len / 2, t), (f.midX + len / 2, t)), ((f.midX - len / 2, b), (f.midX + len / 2, b)),
            ((l, f.midY - len / 2), (l, f.midY + len / 2)), ((r, f.midY - len / 2), (r, f.midY + len / 2)),
          ] {
            marks.move(to: CGPoint(x: a.0, y: a.1))
            marks.addLine(to: CGPoint(x: z.0, y: z.1))
          }
          ctx.stroke(marks, with: .color(.white), style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
          ctx.stroke(marks, with: .color(c.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .allowsHitTesting(false)
        Color.clear.frame(width: f.width, height: f.height).offset(x: f.minX, y: f.minY)
          .accessibilityElement().accessibilityLabel(L("drag_the_corners_or_sides_to_crop")).accessibilityIdentifier("crop-frame")
          .allowsHitTesting(false)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { v in
            if !crop.dragging, v.translation == .zero { crop.touchDown(v.startLocation) }
            crop.drag(v.translation)
          }
          .onEnded { _ in crop.lift() })
    }
  }
}

/// Reset, Cancel and Done, floating at the bottom like the toolbars at the top.
struct CropBar: View {
  var crop: CropModel

  var body: some View {
    HStack(spacing: 8) {
      Button(L("reset")) { withAnimation(Ease.outStrong(duration: 0.2)) { crop.reset() } }.buttonStyle(QuietButtonStyle())
      Button(L("cancel")) { crop.finish(keep: false) }.buttonStyle(QuietButtonStyle())
      Button { crop.finish(keep: true) } label: { Label(L("done"), systemImage: "checkmark") }
        .buttonStyle(PrimaryButtonStyle()).frame(height: 44)
        .accessibilityIdentifier("crop-done")
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .cloudSurface(radius: 22, crown: .softEdge)
    .padding(.bottom, 24)
    .transition(.opacity.combined(with: .offset(y: 20)))
  }
}

/// Crop, offered beside a picture just added (Android's menu shows it first then).
struct CropOffer: View {
  var crop: CropModel
  @Environment(\.tali) private var c

  var body: some View {
    if let p = crop.offered {
      let r = crop.screen(p.rect)
      FloatingBar(crown: .none, height: 48) {
        Button { crop.start() } label: {
          Label(L("crop"), systemImage: "crop").font(TaliType.labelLarge).foregroundStyle(c.ink).padding(.horizontal, 10).frame(height: 40)
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .accessibilityIdentifier("crop-offer")
      }
      .fixedSize()
      .position(x: r.midX, y: max(r.minY - 34, 30))
      .transition(.opacity)
    }
  }
}
