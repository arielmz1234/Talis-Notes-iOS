import SwiftUI

/// The bumps along a cloud surface's top edge (Android's `CloudCrown`).
enum CloudCrown {
  case none
  /// Many small, uneven bumps all along the top edge with a gentle crest near the start, and soft puffs at both ends.
  case edge
  /// Lower, without the crest or end puffs, for small bars.
  case softEdge
  /// A small crown in the middle, like a tiny cloud.
  case center
  /// A low, narrow crown for a single button.
  case little
  /// Two puffs leaning to one side.
  case littleTwin
}

/// A stable pseudo-random number in [0, 1), so the bumps look hand-placed but never change.
private func hash(_ i: Int, _ salt: Int) -> CGFloat {
  let x = sin(Double(i) * 127.1 + Double(salt) * 311.7) * 43758.5453
  return CGFloat(x - floor(x))
}

/// The outline of a cloud surface: a rounded box joined with its crown's puffs (ported from
/// `ui/components/CloudSurface.kt`, so the bumps sit in the same places).
struct CloudShape: Shape {
  var radius: CGFloat = 22
  var crown: CloudCrown = .none

  func path(in rect: CGRect) -> Path {
    let w = rect.width, h = rect.height
    let r = min(radius, h / 2)
    let box = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    let puffs = CGMutablePath()
    func puff(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat) {
      puffs.addEllipse(in: CGRect(x: rect.minX + x - rad, y: rect.minY + y - rad, width: rad * 2, height: rad * 2))
    }
    switch crown {
    case .none: break
    case .edge, .softEdge:
      let soft = crown == .softEdge
      var x = r * 0.55
      var i = 0
      while x < w - r * 0.55 {
        let pr = soft ? 9 + hash(i, 1) * 6 : 10 + hash(i, 1) * 9
        let crest = soft ? 0 : max(0, 1 - abs(x / w - 0.3) / 0.24) * 5
        let rise = soft ? 2.5 + hash(i, 2) * 3 : 4 + hash(i, 2) * 6 + crest
        puff(x, pr - rise, pr)
        x += pr * (1.15 + hash(i, 3) * 0.35)
        i += 1
      }
      if !soft {
        puff(4, h * 0.62, 14)
        puff(w - 4, h * 0.58, 13)
      }
    case .center: for (x, y, rad) in [(-20.0, 6.0, 11.0), (0, 0, 16), (20, 7, 10)] { puff(w / 2 + x, y, rad) }
    case .little: for (x, y, rad) in [(-11.0, 7.0, 7.5), (0, 4, 10), (11, 7.5, 7)] { puff(w / 2 + x, y, rad) }
    case .littleTwin: for (x, y, rad) in [(-6.0, 4.5, 9.5), (9.5, 7.5, 7)] { puff(w / 2 + x, y, rad) }
    }
    if puffs.isEmpty { return Path(box) }
    return Path(box.union(puffs))
  }
}

/// A soft cloud surface behind the content: white fading to a pale blue-lilac belly, a hairline
/// edge, a gentle tinted shadow beneath, and optionally a crown of puffs above the top edge.
struct CloudSurface: ViewModifier {
  var radius: CGFloat = 22
  var crown: CloudCrown = .none
  var shadowDepth: CGFloat = 7
  @Environment(\.tali) private var c
  @AppStorage("minimal") private var minimal = false

  func body(content: Content) -> some View {
    let shape = CloudShape(radius: radius, crown: minimal ? .none : crown)
    content
      .background {
        ZStack {
          shape.fill(
            LinearGradient(
              stops: [.init(color: c.cloudTop, location: 0), .init(color: c.cloudTop, location: 0.5), .init(color: c.cloudBelly, location: 1)],
              startPoint: .top, endPoint: .bottom)
          )
          .shadow(color: c.cloudShadow, radius: 11, x: 0, y: shadowDepth)
          shape.stroke(c.cloudEdge, lineWidth: 1)
        }
      }
      // Solid to touch: nothing under a surface gets a touch that lands on it.
      .contentShape(RoundedRectangle(cornerRadius: radius))
      // What iOS draws itself on a cloud (a switch's track, a field's hint, glass buttons) takes the
      // cloud's look, not the system's: in dark mode a notebook's bars over white paper are light.
      .environment(\.colorScheme, c.isDark ? .dark : .light)
  }
}

extension View {
  func cloudSurface(radius: CGFloat = 22, crown: CloudCrown = .none, shadowDepth: CGFloat = 7) -> some View {
    modifier(CloudSurface(radius: radius, crown: crown, shadowDepth: shadowDepth))
  }
}
