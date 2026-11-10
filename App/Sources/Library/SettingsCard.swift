import SwiftUI

/// Settings: theme (System default, Light, Dark), style (Cloudy or Minimal) and the language, which
/// iOS keeps per app in its own Settings.
struct SettingsCard: View {
  @Environment(\.tali) private var c
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @AppStorage("themeMode") private var themeMode = "LIGHT"
  @AppStorage("minimal") private var minimal = false
  @AppStorage("colorTheme") private var family = ColorTheme.LILAC.rawValue
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text(L("settings")).font(TaliFont.heading(26)).foregroundStyle(c.ink)
        Spacer()
        Button(L("done")) { dismiss() }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("settings-done")
      }
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 24) {
          theme
          style
        }
        VStack(alignment: .leading, spacing: 20) {
          theme
          style
        }
      }
      Text(L("colours")).font(TaliFont.body(15, .bold)).foregroundStyle(c.inkMuted)
      HStack(spacing: 12) {
        ForEach(ColorTheme.allCases) { f in
          Button { withAnimation(.easeOut(duration: 0.25)) { family = f.rawValue } } label: {
            VStack(spacing: 6) {
              FamilyTile(colors: scheme == .dark ? f.dark : f.light)
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.accent, lineWidth: family == f.rawValue ? 2.5 : 0).padding(-3))
              Text(L(f.nameKey)).font(TaliFont.body(13, family == f.rawValue ? .semibold : .regular))
                .foregroundStyle(family == f.rawValue ? c.accent : c.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
            }
          }
          .buttonStyle(.plain)
        }
      }
      Text(minimal ? L("clean_edges_on_bars_and_cards") : L("soft_cloud_edges_on_bars_and"))
        .font(TaliFont.body(14)).foregroundStyle(c.inkMuted)
      HStack(spacing: 14) {
        Text(L("language")).font(TaliFont.body(15, .bold)).foregroundStyle(c.inkMuted)
        Button(currentLanguage) {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        .buttonStyle(QuietButtonStyle())
      }
    }
    .padding(26)
    .frame(maxWidth: 600)
    .cloudSurface(radius: 28, crown: .edge)
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .presentationBackground(.clear)
  }

  private var theme: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L("theme")).font(TaliFont.body(15, .bold)).foregroundStyle(c.inkMuted)
      Picker(L("theme"), selection: $themeMode) {
        Text(L("system_default")).tag("SYSTEM")
        Text(L("light")).tag("LIGHT")
        Text(L("dark")).tag("DARK")
      }
      .pickerStyle(.segmented)
    }
  }

  private var style: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L("style")).font(TaliFont.body(15, .bold)).foregroundStyle(c.inkMuted)
      Picker(L("style"), selection: $minimal) {
        Text(L("cloudy")).tag(false)
        Text(L("minimal")).tag(true)
      }
      .pickerStyle(.segmented)
    }
  }

  /// The app's language, named in itself.
  private var currentLanguage: String {
    let id = Bundle.main.preferredLocalizations.first ?? "en"
    return Locale(identifier: id).localizedString(forIdentifier: id)?.capitalized(with: Locale(identifier: id)) ?? id
  }
}

/// A tiny drawn library in a colour family: its sky and a cloud, a card with a spine and two lines,
/// and the two-tone button.
struct FamilyTile: View {
  var colors: TaliColors

  var body: some View {
    ZStack(alignment: .topLeading) {
      colors.background
      LinearGradient(colors: [colors.skyFrom, colors.skyTo], startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 26)
      Circle().fill(colors.skyCloudTop).frame(width: 16, height: 16).offset(x: 10, y: 8)
      Circle().fill(colors.skyCloudTop).frame(width: 12, height: 12).offset(x: 22, y: 12)
      HStack(spacing: 0) {
        Rectangle().fill(colors.accent).frame(width: 3)
        VStack(alignment: .leading, spacing: 3) {
          Capsule().fill(colors.line).frame(width: 18, height: 2)
          Capsule().fill(colors.line).frame(width: 12, height: 2)
        }
        .padding(4)
      }
      .frame(width: 30, height: 26)
      .background(colors.surface)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .offset(x: 8, y: 32)
      Circle().fill(LinearGradient(colors: [colors.accent, colors.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: 14, height: 14).offset(x: 52, y: 44)
    }
    .frame(width: 76)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}
