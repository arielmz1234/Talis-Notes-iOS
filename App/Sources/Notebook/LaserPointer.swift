import PencilKit
import TaliCore
import UIKit

/// The laser's trails on screen (Android's `drawLaser`): for each stroke a red glow with a bright
/// core, and while it points, a glowing dot with a white-hot middle. `TaliCore.Laser` keeps the timing.
struct LaserState {
  var model = Laser()
  var link: CADisplayLink?
  let layer = CALayer()
  var glows: [CAShapeLayer] = []
  var cores: [CAShapeLayer] = []
  /// How many dots of each trail are in its path, and at which zoom, so only what changed is rebuilt.
  var drawn: [(count: Int, zoom: CGFloat)] = []
  let tip = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
}

/// A display link's target that doesn't keep the canvas alive.
private final class LaserTicker: NSObject {
  weak var owner: NoteCanvas.Coordinator?
  init(_ owner: NoteCanvas.Coordinator) { self.owner = owner }
  @MainActor @objc func tick(_ link: CADisplayLink) {
    guard let owner else {
      link.invalidate()
      return
    }
    owner.laserTick()
  }
}

extension NoteCanvas.Coordinator {
  private static let laserGlow = UIColor(argb: Int32(bitPattern: 0xFFFF_3B4E))
  private static let laserCore = UIColor(argb: Int32(bitPattern: 0xFFFF_6B78))
  private static let laserTip: [(radius: CGFloat, color: UInt32)] = [(11, 0x55FF_3B4E), (5, 0xFFFF_3B4E), (2.2, 0xFFFF_E4E6)]

  func laserBegan(_ p: Pt) {
    own.laser.model.start(p)
    if own.laser.link == nil {
      let link = CADisplayLink(target: LaserTicker(self), selector: #selector(LaserTicker.tick(_:)))
      link.add(to: .main, forMode: .common)
      own.laser.link = link
    }
    drawLaser()
  }

  func laserMoved(_ points: [Pt]) {
    for p in points { own.laser.model.move(p) }
    drawLaser()
  }

  func laserEnded() {
    own.laser.model.end(at: CACurrentMediaTime())
    drawLaser()
  }

  func laserTick() {
    if !own.laser.model.step(at: CACurrentMediaTime()) {
      own.laser.link?.invalidate()
      own.laser.link = nil
    }
    drawLaser()
  }

  private func drawLaser() {
    guard let canvas else { return }
    let z = canvas.zoomScale
    let now = CACurrentMediaTime()
    let trails = own.laser.model.trails
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    while own.laser.glows.count < trails.count {
      for (color, keep) in [(Self.laserGlow, \LaserState.glows), (Self.laserCore, \LaserState.cores)] {
        let l = CAShapeLayer()
        l.fillColor = UIColor.clear.cgColor
        l.strokeColor = color.cgColor
        l.lineCap = .round
        l.lineJoin = .round
        own.laser.layer.addSublayer(l)
        own.laser[keyPath: keep].append(l)
      }
      own.laser.drawn.append((0, 0))
    }
    while own.laser.glows.count > trails.count {
      own.laser.glows.removeFirst().removeFromSuperlayer()
      own.laser.cores.removeFirst().removeFromSuperlayer()
      own.laser.drawn.removeFirst()
    }
    for (i, trail) in trails.enumerated() {
      let life = Laser.life(trail, at: now)
      let glow = own.laser.glows[i], core = own.laser.cores[i]
      if own.laser.drawn[i].count != trail.dots.count || own.laser.drawn[i].zoom != z {
        let path = CGMutablePath()
        if trail.dots.count > 1 { path.addLines(between: trail.dots.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) }) }
        glow.path = path
        core.path = path
        own.laser.drawn[i] = (trail.dots.count, z)
      }
      glow.lineWidth = CGFloat(Laser.glow(life).width)
      glow.opacity = Laser.glow(life).alpha
      core.lineWidth = CGFloat(Laser.core(life).width)
      core.opacity = Laser.core(life).alpha
    }
    let at = own.laser.model.tip
    for (dot, look) in zip(own.laser.tip, Self.laserTip) {
      if dot.superlayer == nil {
        dot.fillColor = UIColor(argb: Int32(bitPattern: look.color)).cgColor
        dot.path = CGPath(ellipseIn: CGRect(x: -look.radius, y: -look.radius, width: look.radius * 2, height: look.radius * 2), transform: nil)
        dot.zPosition = 1
        own.laser.layer.addSublayer(dot)
      }
      dot.isHidden = !own.laser.model.down
      dot.position = CGPoint(x: CGFloat(at.x) * z, y: CGFloat(at.y) * z)
    }
  }
}
