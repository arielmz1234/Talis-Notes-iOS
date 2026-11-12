import PencilKit
import SwiftUI
import TaliCore
import UIKit

/// The screenshot lasso's flash, and where each picture it took came from.
@MainActor
struct ShotState {
  let flash = CAShapeLayer()
  var shooting = false
  /// Where each screenshot was taken from, so a copy pastes back at the same size.
  var areas: [URL: TaliCore.Rect] = [:]
}

/// The screenshot lasso (Android's `takeScreenshot`, `copyScreenshot`): a picture of the rectangle
/// around what she drew, as the page shows it (paper, pages and everything on them; no selection
/// marks or toolbars), sharp enough to zoom into, rendered off the main thread and handed to the
/// screen to save, share or copy.
extension NoteCanvas.Coordinator {
  static let shotFlash: CFTimeInterval = 0.26

  func installShotFlash(on v: PKCanvasView) {
    let flash = lasso.shot.flash
    flash.fillColor = UIColor.white.withAlphaComponent(170 / 255).cgColor
    flash.strokeColor = SelectionChromeView.accent.cgColor
    flash.lineWidth = 2
    flash.opacity = 0
    flash.zPosition = 10
    v.layer.addSublayer(flash)
  }

  func takeScreenshot(_ path: [Pt]) {
    guard let canvas, let pages, let area = Rect.around(path), !ScreenshotLasso.tooSmall(area, zoom: zoom), !lasso.shot.shooting else { return }
    flashShot(area)
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    let world = CGRect(area)
    let px = CGFloat(ScreenshotLasso.pixelsPerUnit(area, zoom: zoom, screenScale: Float(canvas.traitCollection.displayScale)))
    let layer = pages.pages
    let drawing = canvas.drawing
    let theme = ColorTheme.current
    let desk = parent.settings.dark ? UIColor(argb: Int32(bitPattern: 0xFF0E_0C13)) : UIColor(canvas.traitCollection.userInterfaceStyle == .dark ? theme.dark.desk : theme.light.desk)
    let style: UIUserInterfaceStyle = parent.settings.dark ? .dark : .light
    let name = "Tali's Notes " + Self.shotStamp.string(from: Date()) + ".png"
    lasso.shot.shooting = true
    let job = ShotJob(world: world, px: px, layer: layer, drawing: drawing, desk: desk, style: style, name: name)
    DispatchQueue.global(qos: .userInitiated).async {
      let url = job.render()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.lasso.shot.shooting = false
        if let url {
          self.lasso.shot.areas[url] = area
          self.parent.onScreenshot(url)
        } else {
          self.parent.onHint(L("couldn_t_take_the_screenshot"))
        }
      }
    }
  }

  private static let shotStamp: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.dateFormat = "yyyy-MM-dd HH.mm.ss"
    return f
  }()

  /// One screenshot to make, handed to the background.
  private struct ShotJob: @unchecked Sendable {
    var world: CGRect
    var px: CGFloat
    var layer: PagesLayer
    var drawing: PKDrawing
    var desk: UIColor
    var style: UIUserInterfaceStyle
    var name: String

    /// Draws [world] at [px] pixels a unit into `Caches/exports` (older shots there are cleared).
    func render() -> URL? {
    let size = CGSize(width: (world.width * px).rounded(), height: (world.height * px).rounded())
    guard size.width >= 1, size.height >= 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cg = ctx.cgContext
      desk.setFill()
      cg.fill(CGRect(origin: .zero, size: size))
      cg.saveGState()
      cg.scaleBy(x: px, y: px)
      cg.translateBy(x: -world.minX, y: -world.minY)
      cg.clip(to: world)
      layer.paint(in: cg, scale: px)
      cg.restoreGState()
      // The writing, drawn by PencilKit itself in the paper's own style, as on the canvas.
      UITraitCollection(userInterfaceStyle: style).performAsCurrent {
        drawing.image(from: world, scale: px).draw(in: CGRect(origin: .zero, size: size))
      }
    }
    guard let png = image.pngData() else { return nil }
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("exports", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      for old in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where old.pathExtension == "png" { try? FileManager.default.removeItem(at: old) }
      let url = dir.appendingPathComponent(name)
      try png.write(to: url, options: .atomic)
      return url
    } catch {
      return nil
    }
    }
  }

  /// The captured area flashes white and fades, so she sees what was taken.
  private func flashShot(_ area: TaliCore.Rect) {
    let z = CGFloat(zoom)
    let flash = lasso.shot.flash
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    flash.path = UIBezierPath(roundedRect: CGRect(x: CGFloat(area.left) * z, y: CGFloat(area.top) * z, width: CGFloat(area.width) * z, height: CGFloat(area.height) * z), cornerRadius: 6).cgPath
    CATransaction.commit()
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    fade.duration = Self.shotFlash
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    flash.add(fade, forKey: "flash")
  }

  /// Copy on a screenshot: the picture also goes on the app's own clipboard, so holding on the page
  /// pastes it there like anything copied (at the size it was taken, in this notebook or another).
  func copyScreenshot(_ url: URL) {
    guard let area = lasso.shot.areas[url] else { return }
    let file = "shot-" + UUID().uuidString.lowercased() + ".png"
    do {
      try FileManager.default.copyItem(at: url, to: AppFiles.folders.images.appendingPathComponent(file))
    } catch {
      CrashNote.log("copying a screenshot: \(error)")
      return
    }
    Clipboard.items = [.picture(PictureRow(id: "clip", z: 0, file: file, rect: TaliCore.Rect(0, 0, area.width, area.height), front: true))]
  }
}

/// A screenshot taken with the screenshot lasso (Android's `ScreenshotSheet`): a preview, then copy
/// it (to paste on the page by holding, or in another app), save it to Photos, or share it.
struct ScreenshotSheet: View {
  var url: URL
  var onCopy: () -> Void
  var onHint: (String) -> Void
  var onDone: () -> Void
  @Environment(\.tali) private var c
  @State private var image: UIImage?
  @State private var saved = false
  @State private var sharing = false

  var body: some View {
    GeometryReader { geo in
      DialogCard(width: 560) {
        // Close sits in the corner, so the three things to do with it are centred under the picture.
        HStack {
          Text(L("screenshot")).font(TaliType.titleLarge).foregroundStyle(c.ink)
          Spacer()
          Button(action: onDone) {
            Image(systemName: "xmark").font(.system(size: 17, weight: .medium)).foregroundStyle(c.inkMuted).frame(width: 40, height: 40).contentShape(Rectangle())
          }
          .buttonStyle(PressStyle(scale: 0.9))
          .accessibilityLabel(L("close"))
          .accessibilityIdentifier("screenshot-close")
        }
        Spacer().frame(height: 10)
        ZStack {
          RoundedRectangle(cornerRadius: 12).fill(c.sunken)
          if let image {
            Image(uiImage: image).resizable().scaledToFit().padding(6).accessibilityLabel(L("the_screenshot")).accessibilityIdentifier("screenshot-picture")
          }
        }
        .frame(maxWidth: .infinity).frame(height: previewHeight(geo.size.height))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(c.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        Spacer().frame(height: 18)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) { buttons }
          VStack(spacing: 8) { buttons }
        }
        .frame(maxWidth: .infinity)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .task(id: url) { image = UIImage(contentsOfFile: url.path) }
    .sheet(isPresented: $sharing) { ShareSheet(items: [url]) }
  }

  /// As tall as the picture needs between 120 pt and half the screen.
  private func previewHeight(_ screen: CGFloat) -> CGFloat {
    guard let image, image.size.width > 0 else { return 120 }
    let fitted = min(image.size.height / image.size.width * 492, image.size.height / image.scale) + 12
    return min(max(fitted, 120), max(screen * 0.5, 120))
  }

  @ViewBuilder private var buttons: some View {
    Button(L("copy")) {
      // Onto the page (hold anywhere to paste it) and into other apps alike.
      onCopy()
      if let image { UIPasteboard.general.image = image }
      onHint(L("copied_hold_on_the_page_to"))
      onDone()
    }
    .buttonStyle(QuietButtonStyle())
    .accessibilityIdentifier("screenshot-copy")
    Button(saved ? L("saved") : L("save_to_gallery")) {
      guard !saved, let image else { return }
      PhotoSaver.shared.save(image) { ok in
        saved = ok
        onHint(ok ? L("saved") : L("couldn_t_save_the_picture"))
      }
    }
    .buttonStyle(QuietButtonStyle())
    .accessibilityIdentifier("screenshot-save")
    Button {
      sharing = true
    } label: {
      Label(L("share"), systemImage: "square.and.arrow.up")
    }
    .buttonStyle(PrimaryButtonStyle())
    .accessibilityIdentifier("screenshot-share")
  }
}

/// Saves a picture to Photos and says whether it worked.
@MainActor
final class PhotoSaver: NSObject {
  static let shared = PhotoSaver()
  private var waiting: [(Bool) -> Void] = []

  func save(_ image: UIImage, done: @escaping (Bool) -> Void) {
    waiting.append(done)
    UIImageWriteToSavedPhotosAlbum(image, self, #selector(saved(_:error:context:)), nil)
  }

  @objc nonisolated private func saved(_ image: UIImage, error: Error?, context: UnsafeRawPointer?) {
    let ok = error == nil
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        if !self.waiting.isEmpty { self.waiting.removeFirst()(ok) }
      }
    }
  }
}
