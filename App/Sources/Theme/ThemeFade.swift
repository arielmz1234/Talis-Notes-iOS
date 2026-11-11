import UIKit

/// Smooth theme and style changes (Android's `ThemeFade`): just before one, the screen as it looks
/// is captured; the new look is applied underneath and the capture fades away over it. Animating
/// every colour instead would redraw the whole app, painted clouds included, every frame.
@MainActor
enum ThemeFade {
  static func beforeChange() {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let window = scenes.compactMap(\.keyWindow).first, let shot = window.snapshotView(afterScreenUpdates: false) else { return }
    shot.isUserInteractionEnabled = false
    window.addSubview(shot)
    let fade = UIViewPropertyAnimator(duration: 0.45, controlPoint1: CGPoint(x: 0.23, y: 1), controlPoint2: CGPoint(x: 0.32, y: 1)) { shot.alpha = 0 }
    fade.addCompletion { _ in shot.removeFromSuperview() }
    fade.startAnimation()
  }
}
