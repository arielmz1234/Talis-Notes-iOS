import AVFoundation
import CoreImage
import SwiftUI
import TaliCore
import UIKit

/// The app's own camera (Android's `CameraScreen`), for + › Camera and a notebook's Take a photo: the
/// × top left, a big violet shutter, tap to focus, pinch to zoom. A photo goes to the look step
/// (Original, Document, Grey, B&W), where it can be cropped (corners with a magnifier, straightened)
/// and turned. Several photos can be taken before saving; [onSave] gets them upright and finished,
/// as JPEGs.
struct CameraScreen: View {
  var onClose: () -> Void
  var onSave: ([Data]) -> Void

  static var available: Bool { AVCaptureDevice.default(for: .video) != nil }
  static let night = Color(argb: 0xFF0E_0A18)

  var body: some View {
    CameraBody(onClose: onClose, onSave: onSave)
      .environment(\.tali, ColorTheme.current.dark)
      .environment(\.layoutDirection, .leftToRight)
      .preferredColorScheme(.dark)
      .statusBarHidden()
  }
}

/// A photo being finished: the upright picture, a smaller one to show, its crop, look, how the
/// device was held when it was taken, and how many quarter turns she gave it.
private struct Shot {
  var picture: UIImage
  var view: UIImage
  var quad = Quad.whole()
  var look = Look.original
  var held: Int?
  var turns = 0

  init(_ picture: UIImage, held: Int? = nil) {
    self.picture = picture
    view = picture.scaled(maxSide: PageImaging.viewSide)
    self.held = held
  }
}

private enum Step { case crop, look }

private struct CameraBody: View {
  var onClose: () -> Void
  var onSave: ([Data]) -> Void
  @Environment(\.tali) private var c
  @State private var pages: [(data: Data, thumb: UIImage)] = []
  @State private var shot: Shot?
  @State private var step = Step.look
  @State private var working = false
  @State private var discarding = false
  @State private var shown = false

  var body: some View {
    ZStack {
      CameraScreen.night.ignoresSafeArea()
      CameraPart(pages: pages.map(\.thumb), onClose: back, onTaken: { s in
        shot = s
        step = .look
      }, onSave: { finish(nil) })
      if let s = shot {
        EditPart(
          shot: Binding(get: { shot ?? s }, set: { shot = $0 }), step: $step, pages: pages.count, working: working,
          onRetake: { withAnimation(.easeOut(duration: 0.14)) { shot = nil } },
          onAnother: { keep { pages.append($0); withAnimation(.easeOut(duration: 0.14)) { shot = nil } } },
          onSave: { keep { finish($0) } }
        )
        .transition(.opacity.animation(.easeOut(duration: 0.18)))
      }
    }
    .opacity(shown ? 1 : 0)
    .scaleEffect(shown ? 1 : 0.97)
    .onAppear {
      withAnimation(Ease.outStrong(duration: 0.24)) { shown = true }
      if ProcessInfo.processInfo.arguments.contains("-cameraPicture") { shot = Shot(PageImaging.samplePhoto()) }
    }
    .alert(L("cam_discard_title"), isPresented: $discarding) {
      Button(L("cancel"), role: .cancel) {}
      Button(L("cam_discard"), role: .destructive) { onClose() }
    } message: {
      Text(L("cam_discard_body"))
    }
  }

  private func back() {
    if shot != nil {
      shot = nil
    } else if !pages.isEmpty {
      discarding = true
    } else {
      onClose()
    }
  }

  private func finish(_ extra: (data: Data, thumb: UIImage)?) {
    let all = pages + (extra.map { [$0] } ?? [])
    onSave(all.map(\.data))
  }

  /// The photo finished (straightened, its look, as a JPEG) off the main thread; a half turn she gave
  /// it is remembered for the way the device was held.
  private func keep(_ then: @escaping ((data: Data, thumb: UIImage)) -> Void) {
    guard let s = shot, !working else { return }
    working = true
    let (picture, quad, look) = (s.picture, s.quad, s.look)
    Task {
      let done = await Task.detached(priority: .userInitiated) { () -> (Data, UIImage)? in
        let flat = PageImaging.straightened(picture, quad, maxSide: PageImaging.maxSide)
        let finished = PageImaging.looked(flat, look)
        guard let data = finished.jpegData(compressionQuality: 0.9) else { return nil }
        return (data, finished.scaled(maxSide: 120))
      }.value
      if let held = s.held, s.turns % 4 == 2 { CameraTurns.learn(held) }
      working = false
      if let done { then((done.0, done.1)) }
    }
  }
}

// MARK: The camera

/// The live camera and its controls; an iPad held wide has them in a column on the right, upright
/// in a row at the bottom.
private struct CameraPart: View {
  var pages: [UIImage]
  var onClose: () -> Void
  var onTaken: (Shot) -> Void
  var onSave: () -> Void
  @State private var camera = LiveCamera()
  @State private var focus: (at: CGPoint, start: Date)?
  @State private var blink = 0.0
  @State private var zoomAtPinch: CGFloat = 1

  var body: some View {
    GeometryReader { geo in
      let wide = geo.size.width > geo.size.height
      ZStack {
        CameraPreview(camera: camera)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .gesture(
            SpatialTapGesture().onEnded { v in
              camera.focus(at: v.location)
              focus = (v.location, Date())
            })
          .simultaneousGesture(
            MagnifyGesture()
              .onChanged { v in camera.zoom(zoomAtPinch * v.magnification) }
              .onEnded { _ in zoomAtPinch = camera.zoomFactor })
        if let focus {
          TimelineView(.animation) { tl in
            let t = min(tl.date.timeIntervalSince(focus.start) / 0.9, 1)
            let r = 34 * (1.25 - 0.25 * Ease.outStrong(min(1, t * 3)))
            Circle().stroke(Color.white.opacity((1 - t) * 0.9), lineWidth: 1.5).frame(width: r * 2, height: r * 2).position(focus.at)
          }
          .allowsHitTesting(false)
        }
        Color.white.opacity(blink).ignoresSafeArea().allowsHitTesting(false)
        if camera.state != .running { NoCamera(state: camera.state) { camera.askAgain() } }
        VStack {
          HStack {
            RoundButton(icon: "xmark", label: L("close"), action: onClose)
            Spacer()
            if camera.hasFlash {
              RoundButton(icon: camera.flash.icon, label: L("cam_flash")) { camera.flash = camera.flash.next }
            }
          }
          Spacer()
        }
        .padding(20)
        if wide {
          HStack {
            Spacer()
            VStack {
              Spacer()
              Shutter(busy: camera.taking, enabled: camera.state == .running, action: take)
              Spacer().frame(height: 24)
              saveSlot.frame(height: 64)
              Spacer()
            }
            .frame(width: 120)
          }
          .padding(20)
        } else {
          VStack {
            Spacer()
            HStack {
              Spacer().frame(maxWidth: .infinity)
              Shutter(busy: camera.taking, enabled: camera.state == .running, action: take)
              saveSlot.frame(maxWidth: .infinity, alignment: .trailing)
            }
          }
          .padding(20)
        }
      }
    }
    .onAppear { if !ProcessInfo.processInfo.arguments.contains("-cameraPicture") { camera.start() } }
    .onDisappear { camera.stop() }
  }

  @ViewBuilder private var saveSlot: some View {
    if let last = pages.last {
      SavePill(thumb: last, count: pages.count, action: onSave).transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
  }

  private func take() {
    blink = 0.7
    withAnimation(.easeOut(duration: 0.26)) { blink = 0 }
    camera.take { image, held in
      if let image { onTaken(Shot(image, held: held)) }
    }
  }
}

/// The device's camera (AVFoundation): the back camera at photo quality, tap to focus, pinch to zoom,
/// flash when there is one. Photos come out upright for the way the device is held, plus any half turn
/// learned for that way of holding it.
@MainActor @Observable
final class LiveCamera {
  enum State { case starting, running, denied, failed }
  enum Flash {
    case off, auto, on
    var icon: String { self == .off ? "bolt.slash" : (self == .auto ? "bolt.badge.automatic" : "bolt") }
    var next: Flash { self == .off ? .auto : (self == .auto ? .on : .off) }
    var mode: AVCaptureDevice.FlashMode { self == .off ? .off : (self == .auto ? .auto : .on) }
  }

  private(set) var state = State.starting
  private(set) var taking = false
  private(set) var hasFlash = false
  var flash = Flash.off
  private(set) var zoomFactor: CGFloat = 1

  @ObservationIgnored let session = AVCaptureSession()
  @ObservationIgnored private let output = AVCapturePhotoOutput()
  @ObservationIgnored private var device: AVCaptureDevice?
  @ObservationIgnored weak var preview: AVCaptureVideoPreviewLayer?
  @ObservationIgnored private var rotation: AVCaptureDevice.RotationCoordinator?
  @ObservationIgnored private var delegate: PhotoDelegate?

  func start() {
    Task {
      guard await AVCaptureDevice.requestAccess(for: .video) else {
        state = .denied
        return
      }
      guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video),
        let input = try? AVCaptureDeviceInput(device: d)
      else {
        state = .failed
        return
      }
      session.beginConfiguration()
      session.sessionPreset = .photo
      if session.canAddInput(input) { session.addInput(input) }
      if session.canAddOutput(output) { session.addOutput(output) }
      output.maxPhotoQualityPrioritization = .quality
      session.commitConfiguration()
      device = d
      hasFlash = d.hasFlash
      if let preview { rotation = AVCaptureDevice.RotationCoordinator(device: d, previewLayer: preview) }
      nonisolated(unsafe) let s = session
      Self.queue.async { s.startRunning() }
      state = .running
    }
  }

  func stop() {
    nonisolated(unsafe) let s = session
    Self.queue.async { s.stopRunning() }
  }

  /// The session starts and stops off the main thread, one thing at a time.
  private static let queue = DispatchQueue(label: "camera")

  func askAgain() {
    if state == .denied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }

  func focus(at p: CGPoint) {
    guard let d = device, let preview, d.isFocusPointOfInterestSupported else { return }
    let point = preview.captureDevicePointConverted(fromLayerPoint: p)
    try? d.lockForConfiguration()
    d.focusPointOfInterest = point
    d.focusMode = .autoFocus
    if d.isExposurePointOfInterestSupported {
      d.exposurePointOfInterest = point
      d.exposureMode = .autoExpose
    }
    d.unlockForConfiguration()
  }

  func zoom(_ factor: CGFloat) {
    guard let d = device else { return }
    let z = min(max(factor, d.minAvailableVideoZoomFactor), min(d.maxAvailableVideoZoomFactor, 8))
    try? d.lockForConfiguration()
    d.videoZoomFactor = z
    d.unlockForConfiguration()
    zoomFactor = z
  }

  func take(_ done: @escaping (UIImage?, Int?) -> Void) {
    guard state == .running, !taking else { return }
    taking = true
    let held = UIDevice.current.orientation.rawValue
    if let angle = rotation?.videoRotationAngleForHorizonLevelCapture, let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(angle) {
      conn.videoRotationAngle = angle
    }
    let settings = AVCapturePhotoSettings()
    if hasFlash, output.supportedFlashModes.contains(flash.mode) { settings.flashMode = flash.mode }
    settings.photoQualityPrioritization = .quality
    let d = PhotoDelegate { [weak self] data in
      Task { @MainActor in
        guard let self else { return }
        self.taking = false
        self.delegate = nil
        let image = data.flatMap(UIImage.init(data:)).map { $0.upright(maxSide: PageImaging.maxSide).turned(CameraTurns.learned(held)) }
        done(image, held)
      }
    }
    delegate = d
    output.capturePhoto(with: settings, delegate: d)
  }

  private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let done: (Data?) -> Void
    init(_ done: @escaping (Data?) -> Void) { self.done = done }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) { done(photo.fileDataRepresentation()) }
  }
}

/// A half turn she gives a picture before keeping it is remembered per way of holding the device, so
/// a camera that reports itself upside down is right from then on (Android's `learnedTurn`).
enum CameraTurns {
  static func learned(_ held: Int) -> Int { UserDefaults.standard.integer(forKey: "cameraTurn\(held)") }
  static func learn(_ held: Int) { UserDefaults.standard.set((learned(held) + 2) % 4, forKey: "cameraTurn\(held)") }
}

private struct CameraPreview: UIViewRepresentable {
  var camera: LiveCamera

  final class View: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  }

  func makeUIView(context: Context) -> View {
    let v = View()
    v.backgroundColor = UIColor(CameraScreen.night)
    v.preview.session = camera.session
    v.preview.videoGravity = .resizeAspect
    camera.preview = v.preview
    return v
  }

  func updateUIView(_ v: View, context: Context) {}
}

private struct NoCamera: View {
  var state: LiveCamera.State
  var onAllow: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    if state == .denied || state == .failed {
      VStack(spacing: 0) {
        Image(systemName: "video.slash").font(.system(size: 30)).foregroundStyle(c.accent)
        Spacer().frame(height: 12)
        Text(state == .denied ? L("cam_allow_title") : L("cam_unavailable")).font(TaliType.titleMedium).foregroundStyle(c.ink).multilineTextAlignment(.center)
        if state == .denied {
          Spacer().frame(height: 6)
          Text(L("cam_allow_body")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).multilineTextAlignment(.center)
          Spacer().frame(height: 18)
          Button(L("cam_allow"), action: onAllow).buttonStyle(PrimaryButtonStyle())
        }
      }
      .padding(28)
      .frame(maxWidth: 420)
      .quietSurface()
      .padding(32)
    }
  }
}

// MARK: Finishing a photo

private struct EditPart: View {
  @Binding var shot: Shot
  @Binding var step: Step
  var pages: Int
  var working: Bool
  var onRetake: () -> Void
  var onAnother: () -> Void
  var onSave: () -> Void
  @Environment(\.tali) private var c
  @State private var result: UIImage?
  @State private var samples: [Look: UIImage] = [:]
  @State private var turning = false

  var body: some View {
    GeometryReader { geo in
      let wide = geo.size.width > geo.size.height
      let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
      layout {
        ZStack {
          if step == .crop {
            Corners(picture: shot.view, quad: $shot.quad).transition(.opacity)
          } else if let result {
            Image(uiImage: result).resizable().scaledToFit().transition(.opacity)
          }
        }
        .animation(.easeOut(duration: 0.18), value: step)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        panel(wide: wide)
          .padding(16)
          .frame(width: wide ? 332 : nil)
          .frame(maxHeight: wide ? .infinity : nil)
      }
    }
    .background(CameraScreen.night.ignoresSafeArea())
    .task(id: Key(picture: ObjectIdentifier(shot.picture), quad: shot.quad)) {
      let (view, quad, look) = (shot.view, shot.quad, shot.look)
      let made = await Task.detached(priority: .userInitiated) { () -> (UIImage, [Look: UIImage]) in
        let flat = PageImaging.straightened(view, quad, maxSide: PageImaging.viewSide)
        let small = flat.scaled(maxSide: 200)
        var s: [Look: UIImage] = [:]
        for l in Look.allCases { s[l] = PageImaging.looked(small, l) }
        return (PageImaging.looked(flat, look), s)
      }.value
      samples = made.1
      withAnimation(.easeOut(duration: 0.16)) { result = made.0 }
    }
    .onChange(of: shot.look) { _, look in
      let (view, quad) = (shot.view, shot.quad)
      Task {
        let r = await Task.detached(priority: .userInitiated) { PageImaging.looked(PageImaging.straightened(view, quad, maxSide: PageImaging.viewSide), look) }.value
        withAnimation(.easeOut(duration: 0.16)) { result = r }
      }
    }
  }

  private struct Key: Hashable {
    var picture: ObjectIdentifier
    var quad: Quad
  }

  private func panel(wide: Bool) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(step == .crop ? L("cam_crop") : L("cam_look")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      if step == .crop {
        Text(L("cam_corners")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
      } else {
        LookChoices(look: $shot.look, samples: samples, columns: wide ? 2 : 4)
      }
      if wide { Spacer().frame(height: 8) }
      HStack(spacing: 8) {
        SmallTool(icon: "arrow.counterclockwise", label: L("cam_retake"), action: onRetake)
        SmallTool(icon: "rotate.right", label: L("cam_turn"), action: turn)
        if step == .crop {
          let whole = shot.quad == Quad.whole()
          SmallTool(icon: whole ? "crop" : "crop.rotate", label: whole ? L("cam_crop") : L("cam_whole")) {
            shot.quad = whole ? Quad.whole(inset: 0.06) : Quad.whole()
          }
        } else {
          SmallTool(icon: "crop", label: L("cam_crop")) { step = .crop }
        }
      }
      if step == .look {
        HStack(spacing: 8) {
          CompactButton(text: L("cam_another"), icon: "plus", primary: false) { if !working { onAnother() } }
            .accessibilityIdentifier("cam-another")
          CompactButton(text: pages > 0 ? String(format: L("cam_save_n"), pages + 1) : L("save"), icon: "checkmark", primary: true) { if !working { onSave() } }
            .opacity(working ? 0.6 : 1)
            .accessibilityIdentifier("cam-save")
        }
      } else {
        Button { if shot.quad.convex { step = .look } } label: {
          Label(L("tour_next"), systemImage: "arrow.right").frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .opacity(shot.quad.convex ? 1 : 0.4)
        .accessibilityIdentifier("cam-next")
      }
    }
    .padding(20)
    .quietSurface()
  }

  private func turn() {
    guard !turning else { return }
    turning = true
    let s = shot
    Task {
      let t = await Task.detached(priority: .userInitiated) { s.picture.turned(1) }.value
      var n = s
      n.picture = t
      n.view = t.scaled(maxSide: PageImaging.viewSide)
      n.quad = s.quad.turned(1)
      n.turns += 1
      shot = n
      turning = false
    }
  }
}

private struct LookChoices: View {
  @Binding var look: Look
  var samples: [Look: UIImage]
  var columns: Int
  @Environment(\.tali) private var c

  var body: some View {
    let rows = stride(from: 0, to: Look.allCases.count, by: columns).map { Array(Look.allCases[$0..<min($0 + columns, Look.allCases.count)]) }
    VStack(spacing: 10) {
      ForEach(rows, id: \.self) { row in
        HStack(spacing: 10) {
          ForEach(row, id: \.self) { l in
            let on = l == look
            VStack(spacing: 4) {
              ZStack {
                if let s = samples[l] { Image(uiImage: s).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8)) }
              }
              .padding(4)
              .frame(maxWidth: .infinity)
              .frame(height: columns == 2 ? 84 : 64)
              .background(RoundedRectangle(cornerRadius: 12).fill(c.sunken))
              .overlay(RoundedRectangle(cornerRadius: 12).stroke(c.accent.opacity(on ? 1 : 0), lineWidth: 2))
              Text(name(l)).font(TaliType.labelMedium).foregroundStyle(on ? c.ink : c.inkMuted).lineLimit(1)
            }
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { look = l } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("look-\(l.rawValue)")
          }
        }
      }
    }
  }

  private func name(_ l: Look) -> String {
    switch l {
    case .original: L("look_original")
    case .document: L("look_document")
    case .grey: L("look_grey")
    case .blackWhite: L("look_bw")
    }
  }
}

/// The picture with its four corners to drag; a magnifier in the far top corner shows, 2.5×, what's
/// under the corner being dragged.
private struct Corners: View {
  var picture: UIImage
  @Binding var quad: Quad
  @Environment(\.tali) private var c
  @State private var held = -1

  var body: some View {
    GeometryReader { geo in
      let r = fitted(geo.size, picture.size.width / max(picture.size.height, 1))
      let ps = quad.points.map { CGPoint(x: r.minX + CGFloat($0.x) * r.width, y: r.minY + CGFloat($0.y) * r.height) }
      ZStack(alignment: .topLeading) {
        Image(uiImage: picture).resizable().frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        Canvas { ctx, _ in
          var page = Path()
          page.addLines(ps)
          page.closeSubpath()
          var outside = Path(r)
          outside.addPath(page)
          ctx.fill(outside, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
          ctx.stroke(page, with: .color(c.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          for p in ps {
            let dot = Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22))
            ctx.fill(dot, with: .color(.white))
            ctx.stroke(dot, with: .color(c.accent), lineWidth: 3)
          }
        }
        .allowsHitTesting(false)
        if held >= 0 { magnifier(size: geo.size, r: r, at: ps[held], corner: quad.points[held]) }
        ForEach(0..<4, id: \.self) { i in
          Color.clear.frame(width: 22, height: 22).position(ps[i])
            .accessibilityElement().accessibilityLabel(L("cam_corners")).accessibilityIdentifier("corner-\(i)")
            .allowsHitTesting(false)
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { v in
            if held < 0 {
              let i = ps.indices.min { hypot(ps[$0].x - v.startLocation.x, ps[$0].y - v.startLocation.y) < hypot(ps[$1].x - v.startLocation.x, ps[$1].y - v.startLocation.y) }!
              held = hypot(ps[i].x - v.startLocation.x, ps[i].y - v.startLocation.y) < 48 ? i : -2
            }
            guard held >= 0, r.width > 0, r.height > 0 else { return }
            let x = min(max((v.location.x - r.minX) / r.width, 0), 1)
            let y = min(max((v.location.y - r.minY) / r.height, 0), 1)
            quad = quad.with(held, UnitPt(Float(x), Float(y)))
          }
          .onEnded { _ in held = -1 })
    }
  }

  private func magnifier(size: CGSize, r: CGRect, at: CGPoint, corner: UnitPt) -> some View {
    let radius: CGFloat = 58, k: CGFloat = 2.5
    let centre = CGPoint(x: at.x < size.width / 2 ? size.width - radius - 12 : radius + 12, y: radius + 12)
    let circle = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    return ZStack(alignment: .topLeading) {
      ZStack(alignment: .topLeading) {
        CameraScreen.night
        Image(uiImage: picture).resizable().frame(width: r.width * k, height: r.height * k)
          .offset(x: centre.x - CGFloat(corner.x) * r.width * k, y: centre.y - CGFloat(corner.y) * r.height * k)
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
      .mask(Circle().frame(width: circle.width, height: circle.height).offset(x: circle.minX, y: circle.minY).frame(width: size.width, height: size.height, alignment: .topLeading))
      Circle().stroke(.white, lineWidth: 3).frame(width: circle.width, height: circle.height).offset(x: circle.minX, y: circle.minY)
      Path { p in
        p.move(to: CGPoint(x: centre.x - 10, y: centre.y))
        p.addLine(to: CGPoint(x: centre.x + 10, y: centre.y))
        p.move(to: CGPoint(x: centre.x, y: centre.y - 10))
        p.addLine(to: CGPoint(x: centre.x, y: centre.y + 10))
      }
      .stroke(c.accent, lineWidth: 2)
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  /// Where a picture of [aspect] (width / height) sits fitted inside [size].
  private func fitted(_ size: CGSize, _ aspect: CGFloat) -> CGRect {
    guard size.width > 0, size.height > 0 else { return .zero }
    if size.width / size.height > aspect {
      let w = size.height * aspect
      return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
    }
    let h = size.width / aspect
    return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
  }
}

// MARK: Pieces

private struct Shutter: View {
  var busy: Bool
  var enabled: Bool
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Circle().fill(c.accentGradient).padding(8)
        .scaleEffect(busy ? 0.88 : 1)
        .frame(width: 84, height: 84)
        .overlay(Circle().stroke(.white, lineWidth: 4))
        .overlay {
          if busy {
            TimelineView(.animation) { tl in
              Circle().trim(from: 0, to: 0.25).stroke(c.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
            }
          }
        }
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .disabled(!enabled || busy)
    .opacity(enabled ? 1 : 0.4)
    .accessibilityLabel(L("cam_take"))
    .accessibilityIdentifier("cam-take")
  }
}

private struct RoundButton: View {
  var icon: String
  var label: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(Circle().fill(Color(argb: 0x9E1B_1430)))
        .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .accessibilityLabel(label)
  }
}

private struct SavePill: View {
  var thumb: UIImage
  var count: Int
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(uiImage: thumb).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 1.5))
          .overlay(alignment: .topTrailing) {
            Text("\(count)").font(TaliType.labelSmall).foregroundStyle(c.accent).frame(width: 20, height: 20).background(Circle().fill(.white)).offset(x: 6, y: -6)
          }
        Text(L("save")).font(TaliType.labelLarge).foregroundStyle(c.onAccent)
      }
      .padding(.leading, 6).padding(.trailing, 14)
      .frame(height: 56)
      .background(RoundedRectangle(cornerRadius: 18).fill(c.accentGradient))
    }
    .buttonStyle(PressStyle(scale: 0.95))
  }
}

private struct SmallTool: View {
  var icon: String
  var label: String
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 19)).foregroundStyle(c.accent)
        Text(label).font(TaliType.labelSmall).foregroundStyle(c.ink).lineLimit(2).multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 4)
      .background(RoundedRectangle(cornerRadius: 14).fill(c.sunken))
    }
    .buttonStyle(PressStyle(scale: 0.95))
    .accessibilityIdentifier("cam-\(label)")
  }
}

private struct CompactButton: View {
  var text: String
  var icon: String
  var primary: Bool
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 15))
        Text(text).font(TaliType.labelLarge).lineLimit(1)
      }
      .foregroundStyle(primary ? c.onAccent : c.ink)
      .frame(maxWidth: .infinity).frame(height: 40).padding(.horizontal, 10)
      .background(RoundedRectangle(cornerRadius: 12).fill(primary ? AnyShapeStyle(c.accentGradient) : AnyShapeStyle(c.sunken)))
    }
    .buttonStyle(PressStyle(scale: 0.95))
  }
}

extension View {
  /// The camera's one surface: a faint lilac glass with a hairline edge, no cloud bumps.
  fileprivate func quietSurface() -> some View {
    background(RoundedRectangle(cornerRadius: 24).fill(Color(argb: 0xFF1A_1428)))
      .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(argb: 0xFFB7_9CFF).opacity(0.16), lineWidth: 1))
  }
}
