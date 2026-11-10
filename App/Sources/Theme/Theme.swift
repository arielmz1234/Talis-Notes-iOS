import SwiftUI
import UIKit

extension Color {
  /// From an Android-style 0xAARRGGBB value.
  init(argb: UInt32) {
    self.init(
      .sRGB, red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255, blue: Double(argb & 0xFF) / 255,
      opacity: Double((argb >> 24) & 0xFF) / 255)
  }
}

/// The app's colours, ported from Android's `theme/Theme.kt` (`TaliColors`): soft lilac surfaces
/// meeting light blues, plum-tinted ink for text, violet-to-blue for actions.
struct TaliColors: Sendable {
  var background: Color
  var surface: Color
  var sidebar: Color
  var sunken: Color
  var line: Color
  var ink: Color
  var inkMuted: Color
  var inkFaint: Color
  var accent: Color
  var onAccent: Color
  var accentSoft: Color
  var lilac: Color
  var lilacDeep: Color
  var amber: Color
  var danger: Color
  var scrim: Color
  var paper: Color
  var blue: Color
  var blueSoft: Color
  var sky: Color
  var sidebarEnd: Color
  var isDark: Bool
  var cloudTop: Color
  var cloudBelly: Color
  var cloudEdge: Color
  var cloudShadow: Color
  var skyFrom = Color(argb: 0xFFBF_D4FF)
  var skyTo = Color(argb: 0xFFDC_CBFF)
  var skyCloudTop = Color(argb: 0xFFFF_FFFF)
  var skyCloudMid = Color(argb: 0xFFD3_D9FA)
  var skyCloudLow = Color(argb: 0xFFB3_B8EF)
  var skyCloudShadow = Color(argb: 0x2962_56C8)
  var glow = Color(argb: 0xFF3B_2A7A)
  var dusk = Color(argb: 0xFFB7_A6EE)
  var desk = Color(argb: 0xFFE9_E4F2)

  var accentGradient: LinearGradient { LinearGradient(colors: [accent, blue], startPoint: .topLeading, endPoint: .bottomTrailing) }

  static let lilacLight = TaliColors(
    background: Color(argb: 0xFFF7_F3FF), surface: Color(argb: 0xFFFF_FFFF), sidebar: Color(argb: 0xFFEF_E6FF),
    sunken: Color(argb: 0xFFEE_E6FC), line: Color(argb: 0xFFE3_D8F7), ink: Color(argb: 0xFF1F_1A2E), inkMuted: Color(argb: 0xFF66_5D7D),
    inkFaint: Color(argb: 0xFF9D_94B5), accent: Color(argb: 0xFF7A_4ED6), onAccent: .white, accentSoft: Color(argb: 0xFFE6_D8FE),
    lilac: Color(argb: 0xFFDF_C4FF), lilacDeep: Color(argb: 0xFFD1_AEFF), amber: Color(argb: 0xFFF2_B53A), danger: Color(argb: 0xFFD1_435B),
    scrim: Color(argb: 0x661F_1A2E), paper: .white, blue: Color(argb: 0xFF4F_7BE8), blueSoft: Color(argb: 0xFFE8_F1FF),
    sky: Color(argb: 0xFFD6_E6FF), sidebarEnd: Color(argb: 0xFFE6_EFFF), isDark: false, cloudTop: .white,
    cloudBelly: Color(argb: 0xFFE3_E8FC), cloudEdge: Color(argb: 0xFFCD_D4F5), cloudShadow: Color(argb: 0x3D62_56C8))

  static let lilacDark = TaliColors(
    background: Color(argb: 0xFF15_111E), surface: Color(argb: 0xFF21_1B2E), sidebar: Color(argb: 0xFF1B_1627),
    sunken: Color(argb: 0xFF2B_2340), line: Color(argb: 0xFF38_2E50), ink: Color(argb: 0xFFF0_EAFF), inkMuted: Color(argb: 0xFFB3_A8CC),
    inkFaint: Color(argb: 0xFF7D_7394), accent: Color(argb: 0xFFC4_A8FF), onAccent: Color(argb: 0xFF21_163C), accentSoft: Color(argb: 0xFF3A_2D5C),
    lilac: Color(argb: 0xFF4A_3A73), lilacDeep: Color(argb: 0xFF6A_54A3), amber: Color(argb: 0xFFF2_B53A), danger: Color(argb: 0xFFFF_7A8E),
    scrim: Color(argb: 0x9900_0000), paper: .white, blue: Color(argb: 0xFF8F_B0FF), blueSoft: Color(argb: 0xFF22_304F),
    sky: Color(argb: 0xFF2E_4470), sidebarEnd: Color(argb: 0xFF16_1C2B), isDark: true, cloudTop: Color(argb: 0xFF3A_335E),
    cloudBelly: Color(argb: 0xFF2B_2548), cloudEdge: Color(argb: 0xFF51_4980), cloudShadow: Color(argb: 0x3800_0000),
    skyFrom: Color(argb: 0xFF1D_2A52), skyTo: Color(argb: 0xFF30_245A), skyCloudTop: Color(argb: 0xFFE4_E1F7),
    skyCloudMid: Color(argb: 0xFF9A_A0DC), skyCloudLow: Color(argb: 0xFF7C_7CC8), skyCloudShadow: Color(argb: 0x4000_0000),
    desk: Color(argb: 0xFF2A_2338))
}

extension TaliColors {
  /// A notebook's bars in dark mode while the page is white: soft lilac clouds rather than deep plum,
  /// so they sit gently on the paper (Android's `LilacMist`).
  static let lilacMist: TaliColors = {
    var m = TaliColors.lilacLight
    m.surface = Color(argb: 0xFFF5_EFFF)
    m.sunken = Color(argb: 0xFFE6_DBFB)
    m.line = Color(argb: 0xFFD5_C7F2)
    m.ink = Color(argb: 0xFF26_1D3B)
    m.inkMuted = Color(argb: 0xFF5D_5279)
    m.inkFaint = Color(argb: 0xFF8C_82AA)
    m.accentSoft = Color(argb: 0xFFE0_D1FD)
    m.blueSoft = Color(argb: 0xFFE1_EAFF)
    m.cloudTop = Color(argb: 0xFFF1_E9FF)
    m.cloudBelly = Color(argb: 0xFFDC_CEF9)
    m.cloudEdge = Color(argb: 0xFFC6_B5EE)
    m.cloudShadow = Color(argb: 0x4D2A_1F55)
    return m
  }()
}

private struct TaliColorsKey: EnvironmentKey {
  static let defaultValue = TaliColors.lilacLight
}

extension EnvironmentValues {
  var tali: TaliColors {
    get { self[TaliColorsKey.self] }
    set { self[TaliColorsKey.self] = newValue }
  }
}

/// Fonts as on Android: Figtree for text and Bricolage Grotesque for headings (optical size and a
/// slightly narrow width, as `theme/Theme.kt` sets them), Heebo in Hebrew and Vazirmatn in Arabic
/// (Figtree and Bricolage have no Hebrew or Arabic letters). All four are variable fonts, so the
/// weight is set on their axes.
enum TaliFont {
  static var language: String {
    let id = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
    return Locale(identifier: id).language.languageCode?.identifier ?? "en"
  }

  private static func numeric(_ w: Font.Weight) -> CGFloat {
    switch w {
    case .ultraLight: 200
    case .thin: 250
    case .light: 300
    case .medium: 500
    case .semibold: 600
    case .bold: 700
    case .heavy: 800
    case .black: 900
    default: 400
    }
  }

  private static func tag(_ s: String) -> Int { s.unicodeScalars.reduce(0) { $0 << 8 | Int($1.value) } }

  private static func variable(_ postScript: String, _ size: CGFloat, _ axes: [String: CGFloat]) -> Font {
    var variations: [Int: CGFloat] = [:]
    for (k, v) in axes { variations[tag(k)] = v }
    let d = UIFontDescriptor(fontAttributes: [
      .name: postScript, UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
    ])
    return Font(UIFont(descriptor: d, size: size) as CTFont)
  }

  static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    let w = numeric(weight)
    switch language {
    case "he": return variable("Heebo-Regular", size, ["wght": w])
    case "ar": return variable("Vazirmatn-Regular", size, ["wght": w])
    default: return variable("Figtree-Light", size, ["wght": w])
    }
  }

  static func heading(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
    let w = numeric(weight)
    switch language {
    case "he": return variable("Heebo-Regular", size, ["wght": w])
    case "ar": return variable("Vazirmatn-Regular", size, ["wght": w])
    default: return variable("BricolageGrotesque-96ptExtraBold", size, ["wght": min(w, 800), "opsz": min(max(size * 1.5, 12), 96), "wdth": 92])
    }
  }
}

/// Picks light or dark colours from the system's colour scheme.
struct TaliTheme: ViewModifier {
  @Environment(\.colorScheme) private var scheme
  func body(content: Content) -> some View {
    let colors = scheme == .dark ? TaliColors.lilacDark : TaliColors.lilacLight
    content.environment(\.tali, colors).tint(colors.accent)
  }
}

extension View {
  func taliTheme() -> some View { modifier(TaliTheme()) }
}

/// Sizes that differ on a phone (the Android app's `PHONE_DP`, 600).
enum Layout {
  static let phoneWidth: CGFloat = 600
}
