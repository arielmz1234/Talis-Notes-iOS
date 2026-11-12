import PencilKit
import TaliCore
import UIKit

/// A finger held on a locked item, and the padlock shown as things lock and unlock.
@MainActor
struct LockState {
  var watcher: StrokeWatcher?
  /// The locked item a finger is being held on (to unlock it), and where the finger came down.
  var target: String?
  var fingerAt: CGPoint = .zero
  var timer: Timer?
  /// When the pencil last touched: a hand resting while she writes mustn't unlock anything.
  var lastPencilAt: Date?
  /// When a hold last unlocked something: the finger lifting afterwards isn't a tap.
  var unlockedAt: Date?
  let cues = LockCueView()
}

/// Lock (Android's `lockSelection`, `longPress`, `unlockAll`): locked items are left alone by the
/// lasso, taps and the eraser. Lock from the selection menu; unlock by holding a finger on it, or
/// all at once from the ⋯ menu. All are undoable. Locked writing is kept out of PencilKit's
/// drawing (the page draws it), so nothing of PencilKit's can change it.
extension NoteCanvas.Coordinator {
  /// A finger held still this long on a locked item unlocks it (Android's `LONG_PRESS_MS`).
  static let unlockHold: TimeInterval = 1.5
  /// A hand that just put the pencil down isn't unlocking anything (`PEN_NEARBY_MS`).
  static let pencilNearby: TimeInterval = 1.5
  /// A contact with a bigger radius than this (points) is a palm, not a fingertip. Android's
  /// `PALM_MM` is 14 mm across; iOS reports a fingertip as up to about 40 pt, so the line is drawn
  /// a little above that.
  static let palmRadius: CGFloat = 45
  /// The padlock shows over the item, unless the finger covers that spot: then this far above it (`HOLD_LIFT_DP`).
  static let holdLift: CGFloat = 64

  func installLock(on v: PKCanvasView) {
    let w = StrokeWatcher(target: nil, action: nil)
    w.delegate = self
    w.accepts = { [weak self] t in self?.holdsLock(t) ?? false }
    w.began = { [weak self] t, _ in self?.lockHoldBegan(t) }
    w.moved = { [weak self] t, _ in self?.lockHoldMoved(t) }
    w.ended = { [weak self] _ in self?.cancelLockHold() }
    v.addGestureRecognizer(w)
    lasso.lock.watcher = w
    v.addSubview(lasso.lock.cues)
  }

  var lockedCount: Int { pageItems.filter(\.locked).count }

  /// Locks what's picked up in place. Picked up while locked (the lasso can be set to), the same
  /// button unlocks it.
  func lockSelection() {
    let items = pickedItems
    guard !items.isEmpty, let bounds = lasso.bounds else { return }
    let centre = Pt(Float(bounds.midX), Float(bounds.midY))
    if items.allSatisfy(\.locked) {
      let unlocked = items.map { $0.withLocked(false) }
      commit(remove: items, add: unlocked)
      setSelection(lasso.picked, menu: nil)
      playLockCue(at: centre, locking: false)
      parent.onHint(unlocked.count == 1 ? L("unlocked") : L("n_items_unlocked", unlocked.count))
      return
    }
    playLockCue(at: centre, locking: true)
    clearSelection()
    commit(remove: items, add: items.map { $0.withLocked(true) })
    parent.onHint(items.count == 1 ? L("locked_hold_it_to_unlock") : L("n_items_locked_hold_one_to", items.count))
  }

  func unlockAll() {
    let locked = pageItems.filter(\.locked)
    guard !locked.isEmpty else { return }
    clearSelection()
    commit(remove: locked, add: locked.map { $0.withLocked(false) })
    parent.onHint(locked.count == 1 ? L("t_1_item_unlocked") : L("n_items_unlocked", locked.count))
  }

  // MARK: Hold to unlock

  private func fingertip(_ t: UITouch) -> Bool { t.majorRadius <= Self.palmRadius }

  /// A finger that doesn't write, fingertip-sized, on a locked item, with no pencil at work just before.
  private func holdsLock(_ t: UITouch) -> Bool {
    guard t.type == .direct, !draws(t), !parent.viewOnly, textEdit.view == nil, claim(t) == nil, fingertip(t) else { return false }
    if let pencil = lasso.lock.lastPencilAt, Date().timeIntervalSince(pencil) < Self.pencilNearby { return false }
    return item(at: worldPoint(of: t), locked: true) != nil
  }

  private func lockHoldBegan(_ t: UITouch) {
    guard let canvas else { return }
    let at = t.location(in: canvas)
    guard let target = item(at: Pt(at) / zoom, locked: true) else { return }
    lasso.lock.target = target.id
    lasso.lock.fingerAt = at
    // The padlock shows over the item, unless the finger is covering that spot: then just above it.
    let centre = target.bounds.center
    let onScreen = CGPoint(centre * zoom)
    let shownAt = hypot(onScreen.x - at.x, onScreen.y - at.y) > Self.holdLift ? centre : Pt(CGPoint(x: at.x, y: at.y - Self.holdLift)) / zoom
    lasso.lock.cues.hold(at: shownAt, over: canvas)
    lasso.lock.timer?.invalidate()
    lasso.lock.timer = Timer.scheduledTimer(withTimeInterval: Self.unlockHold, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.unlockHeld() }
    }
  }

  /// A hold to unlock must stay put and stay fingertip-sized (a palm rolling down grows).
  private func lockHoldMoved(_ t: UITouch) {
    guard let canvas, lasso.lock.target != nil else { return }
    let at = t.location(in: canvas)
    if hypot(at.x - lasso.lock.fingerAt.x, at.y - lasso.lock.fingerAt.y) > 5 || !fingertip(t) { cancelLockHold() }
  }

  private func cancelLockHold() {
    lasso.lock.timer?.invalidate()
    lasso.lock.timer = nil
    guard lasso.lock.target != nil else { return }
    lasso.lock.target = nil
    // Let go early: whatever of the padlock had appeared fades away quickly.
    lasso.lock.cues.letGo()
  }

  /// The finger stayed: the item under it unlocks, a fill and its outline together, as they were
  /// locked together, and it's picked up.
  private func unlockHeld() {
    guard let canvas, let target = lasso.lock.target else { return }
    lasso.lock.timer = nil
    lasso.lock.target = nil
    guard let item = item(at: Pt(lasso.lock.fingerAt) / zoom, locked: true), item.id == target else {
      lasso.lock.cues.letGo()
      return
    }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let ids = Set(withFills([item.id], pickLocked: true))
    let group = pageItems.filter { ids.contains($0.id) && $0.locked }
    commit(remove: group, add: group.map { $0.withLocked(false) })
    lasso.lock.unlockedAt = Date()
    setSelection(Set(group.map(\.id)), menu: true)
    // The padlock that filled up over it pops open and goes.
    lasso.lock.cues.unlockedFromHold(over: canvas)
    parent.onHint(L("unlocked_it_can_be_picked_up"))
  }

  func playLockCue(at world: Pt, locking: Bool) {
    guard let canvas else { return }
    lasso.lock.cues.play(at: world, locking: locking, over: canvas)
  }
}

/// A small padlock in a frosted chip (Android's `LockGlyph` and `drawLockCues`), shown when something
/// is locked or unlocked. It comes in from 90% with a strong ease-out, the shackle clicks shut or
/// swings open, then it rises a touch and fades, a little faster out than in. While a finger is held
/// on a locked item, a ring round the chip fills as she holds.
final class LockCueView: UIView {
  private struct Cue {
    var at: Pt
    var locking: Bool
    var start: CFTimeInterval
    var fromHold = false
  }

  private struct Fade {
    var start: CFTimeInterval
    var alpha: CGFloat
    var progress: CGFloat
    var at: Pt
  }

  private static let ringDelay: CFTimeInterval = 0.5
  private static let appear: CFTimeInterval = 0.2
  private static let shackleFrom: CFTimeInterval = 0.26
  private static let shackleTime: CFTimeInterval = 0.3
  private static let leaveFrom: CFTimeInterval = 1.05
  private static let total: CFTimeInterval = 1.3

  private var cue: Cue?
  private var holding: (at: Pt, since: CFTimeInterval)?
  private var fade: Fade?
  private weak var canvas: UIScrollView?
  private var link: CADisplayLink?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = false
    isHidden = true
    layer.zPosition = 12
  }

  required init?(coder: NSCoder) { fatalError() }

  func play(at world: Pt, locking: Bool, over canvas: UIScrollView) {
    cue = Cue(at: world, locking: locking, start: CACurrentMediaTime())
    run(over: canvas)
  }

  func hold(at world: Pt, over canvas: UIScrollView) {
    holding = (world, CACurrentMediaTime())
    run(over: canvas)
  }

  /// The finger left early: the padlock fades from how it looked.
  func letGo() {
    if let shown = holdProgress(CACurrentMediaTime()), let h = holding { fade = Fade(start: CACurrentMediaTime(), alpha: shown.alpha, progress: shown.progress, at: h.at) }
    holding = nil
  }

  /// The hold came through: the same unlock as the menu's, from the snap on.
  func unlockedFromHold(over canvas: UIScrollView) {
    guard let h = holding else { return }
    holding = nil
    cue = Cue(at: h.at, locking: false, start: CACurrentMediaTime() - Self.appear, fromHold: true)
    run(over: canvas)
  }

  private func run(over canvas: UIScrollView) {
    self.canvas = canvas
    isHidden = false
    place()
    if link == nil {
      let l = CADisplayLink(target: self, selector: #selector(tick))
      l.add(to: .main, forMode: .common)
      link = l
    }
    setNeedsDisplay()
  }

  @objc private func tick() {
    if cue == nil && holding == nil && fade == nil {
      link?.invalidate()
      link = nil
      isHidden = true
      return
    }
    place()
    setNeedsDisplay()
  }

  /// Over what's on screen, in the canvas's own coordinates.
  private func place() {
    guard let canvas, frame != canvas.bounds else { return }
    frame = canvas.bounds
    bounds.origin = canvas.bounds.origin
  }

  private func easeOut(_ t: CGFloat) -> CGFloat {
    let k = 1 - min(max(t, 0), 1)
    return 1 - k * k * k
  }

  private func holdProgress(_ now: CFTimeInterval) -> (alpha: CGFloat, progress: CGFloat)? {
    guard let h = holding else { return nil }
    let since = now - h.since - Self.ringDelay
    if since <= 0 { return nil }
    return (easeOut(since / 0.2), min(since / (NoteCanvas.Coordinator.unlockHold - Self.ringDelay), 1))
  }

  override func draw(_ rect: CGRect) {
    guard let cg = UIGraphicsGetCurrentContext(), let canvas else { return }
    let z = canvas.zoomScale
    let now = CACurrentMediaTime()
    func screen(_ p: Pt) -> CGPoint { CGPoint(x: CGFloat(p.x) * z, y: CGFloat(p.y) * z) }
    let dark = traitCollection.userInterfaceStyle == .dark
    if let shown = holdProgress(now), let h = holding {
      padlock(cg, at: screen(h.at), alpha: shown.alpha, scale: 0.9 + 0.1 * shown.alpha, open: 0, progress: shown.progress, dark: dark)
    }
    if let f = fade {
      let t = CGFloat((now - f.start) / 0.12)
      if t >= 1 { fade = nil } else { padlock(cg, at: screen(f.at), alpha: f.alpha * (1 - t), scale: 1 - 0.04 * t, open: 0, progress: f.progress, dark: dark) }
    }
    if let c = cue {
      let t = now - c.start
      if t >= Self.total {
        cue = nil
      } else {
        let appear = c.fromHold ? 1 : easeOut(t / Self.appear)
        let leave = easeOut((t - Self.leaveFrom) / (Self.total - Self.leaveFrom))
        // The shackle moves with a small overshoot, like a real lock snapping.
        let k = CGFloat(min(max((t - Self.shackleFrom) / Self.shackleTime, 0), 1))
        let click = 1 + 2.2 * pow(k - 1, 3) + 1.2 * pow(k - 1, 2)
        let open = c.locking ? 1 - click : click
        // A slight pulse of the chip as it clicks.
        let pulseT = CGFloat(min(max((t - Self.shackleFrom - Self.shackleTime * 0.6) / 0.2, 0), 1))
        let pulse = 0.06 * sin(.pi * pulseT)
        let at = screen(c.at)
        padlock(cg, at: CGPoint(x: at.x, y: at.y - 6 * leave), alpha: appear * (1 - leave), scale: (0.9 + 0.1 * appear) + pulse - 0.05 * leave, open: open, progress: -1, dark: dark)
      }
    }
  }

  /// A padlock centred at [at]; [open] 0 is shut, 1 is the shackle lifted and swung open. [progress]
  /// 0...1 draws a ring round the chip filling clockwise (a hold to unlock); below 0, none.
  private func padlock(_ cg: CGContext, at: CGPoint, alpha: CGFloat, scale: CGFloat, open: CGFloat, progress: CGFloat, dark: Bool) {
    if alpha <= 0.01 { return }
    // A little larger than a toolbar icon, so the lock is easy to see happen.
    let d: CGFloat = 1.3
    let chip = dark ? UIColor(argb: Int32(bitPattern: 0xFF2E_2848)) : .white
    let ink = dark ? UIColor(argb: Int32(bitPattern: 0xFFC8_B4FF)) : UIColor(argb: Int32(bitPattern: 0xFF7A_4FD8))
    cg.saveGState()
    cg.translateBy(x: at.x, y: at.y)
    cg.scaleBy(x: scale, y: scale)
    cg.setAlpha(alpha)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 2 * d), blur: 8 * d, color: (dark ? UIColor.black.withAlphaComponent(0.33) : UIColor(argb: Int32(bitPattern: 0x333B_2A7A))).cgColor)
    cg.setFillColor(chip.withAlphaComponent(235 / 255).cgColor)
    cg.fillEllipse(in: CGRect(x: -21 * d, y: -21 * d, width: 42 * d, height: 42 * d))
    cg.restoreGState()
    if progress >= 0 {
      let r = 21 * d + 3
      cg.setLineWidth(2.6)
      cg.setLineCap(.round)
      cg.setStrokeColor(ink.withAlphaComponent(50 / 255).cgColor)
      cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
      cg.setStrokeColor(ink.cgColor)
      cg.addArc(center: .zero, radius: r, startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * min(max(progress, 0), 1), clockwise: false)
      cg.strokePath()
    }
    // The body, and its keyhole.
    cg.setFillColor(ink.cgColor)
    cg.addPath(UIBezierPath(roundedRect: CGRect(x: -7.5 * d, y: -1.5 * d, width: 15 * d, height: 11 * d), cornerRadius: 2.6 * d).cgPath)
    cg.fillPath()
    cg.setFillColor(chip.cgColor)
    cg.fillEllipse(in: CGRect(x: -1.5 * d, y: 1.9 * d, width: 3 * d, height: 3 * d))
    // The shackle: lifts and swings round its right leg as it opens.
    cg.translateBy(x: 0, y: -3.5 * d * open)
    cg.translateBy(x: 4.6 * d, y: -1.5 * d)
    cg.rotate(by: -28 * open * .pi / 180)
    cg.translateBy(x: -4.6 * d, y: 1.5 * d)
    cg.setStrokeColor(ink.cgColor)
    cg.setLineWidth(2.2 * d)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: -4.6 * d, y: -1.2 * d))
    cg.addLine(to: CGPoint(x: -4.6 * d, y: -4.5 * d))
    cg.addArc(center: CGPoint(x: 0, y: -4.5 * d), radius: 4.6 * d, startAngle: .pi, endAngle: 0, clockwise: false)
    cg.addLine(to: CGPoint(x: 4.6 * d, y: -1.2 * d))
    cg.strokePath()
    cg.restoreGState()
  }
}
