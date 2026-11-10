import SwiftUI

/// Settings: theme (System default, Light, Dark), style (Cloudy or Minimal) and the language, which
/// iOS keeps per app in its own Settings.
struct SettingsCard: View {
  @Environment(\.tali) private var c
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @AppStorage("themeMode") private var themeMode = "LIGHT"
  @AppStorage("minimal") private var minimal = false

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
