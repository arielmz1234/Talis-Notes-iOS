import SwiftUI

/// Settings, laid out as Android's `SettingsDialog`: Language, Colours (four tiles, each a tiny
/// library in that family), Theme beside Style, a line about the style, then Done, and who made it.
/// The language is iOS's own per-app setting, so its row opens the app's page in iOS Settings.
struct SettingsCard: View {
  var onClose: () -> Void = {}
  var onTour: () -> Void = {}
  @Environment(\.tali) private var c
  @Environment(\.openURL) private var openURL
  @Environment(\.colorScheme) private var scheme
  @AppStorage("themeMode") private var themeMode = "LIGHT"
  @AppStorage("minimal") private var minimal = false
  @AppStorage("colorTheme") private var family = ColorTheme.LILAC.rawValue
  @AppStorage("pdfsToLibrary") private var pdfsToLibrary = false
  @Namespace private var ring

  var body: some View {
    DialogCard(width: 600) {
      Text(L("settings")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 18)
      CardBody {
        SectionLabel(text: L("language"))
        Spacer().frame(height: 8)
        languageRow
        Spacer().frame(height: 18)
        SectionLabel(text: L("colours"))
        Spacer().frame(height: 8)
        colours
        Spacer().frame(height: 18)
        ThemeBesideStyle {
          themeChoice
          styleChoice
        }
        Spacer().frame(height: 6)
        Text(minimal ? L("clean_edges_on_bars_and_cards") : L("soft_cloud_edges_on_bars_and"))
          .font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
        Spacer().frame(height: 18)
        SectionLabel(text: L("pdfs_from_other_apps"))
        Spacer().frame(height: 4)
        ToggleRow(
          label: L("add_them_to_my_notebooks"), on: $pdfsToLibrary,
          detail: pdfsToLibrary ? L("a_pdf_you_open_with_tali") : L("a_pdf_you_open_with_tali_2"))
      }
      Spacer().frame(height: 22)
      HStack(spacing: 0) {
        Button(L("take_the_tour"), action: onTour).buttonStyle(QuietButtonStyle()).accessibilityIdentifier("take-tour")
        Spacer(minLength: 8)
        Button(L("done")) { onClose() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("settings-done")
      }
      Spacer().frame(height: 14)
      Text(L("made_by_n", "Ariel M.") + " · " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
        .font(TaliType.labelSmall).foregroundStyle(c.inkFaint).frame(maxWidth: .infinity)
    }
  }

  private var languageRow: some View {
    Button {
      if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(c.accent)
        Text(currentLanguage).font(TaliType.titleSmall).foregroundStyle(c.ink)
        Spacer()
        Image(systemName: "chevron.down").font(.system(size: 15, weight: .medium)).foregroundStyle(c.inkMuted)
      }
      .padding(.horizontal, 14)
      .frame(height: 52)
      .background(RoundedRectangle(cornerRadius: 16).fill(c.surface))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line, lineWidth: 1))
    }
    .buttonStyle(PressStyle(scale: 0.98))
    .accessibilityLabel(L("language"))
  }

  private var colours: some View {
    HStack(spacing: 10) {
      ForEach(ColorTheme.allCases) { f in
        let on = family == f.rawValue
        Button {
          ThemeFade.beforeChange()
          family = f.rawValue
        } label: {
          VStack(spacing: 6) {
            ThemePreview(p: scheme == .dark ? f.dark : f.light).frame(height: 78)
            Text(L(f.nameKey)).font(TaliType.labelLarge).foregroundStyle(on ? c.accent : c.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
            Spacer().frame(height: 2)
          }
          .padding(5)
          .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .frame(maxWidth: .infinity)
        .slidingOption(f.rawValue, in: ring)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("colours-\(f.rawValue)")
      }
    }
    .slidingHighlight(ring, selected: family, fill: .color(c.accent), corner: 20, ring: 2.5)
  }

  private var themeChoice: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: L("theme"))
      Segmented(options: ["SYSTEM", "LIGHT", "DARK"], selected: faded($themeMode)) { mode in
        switch mode {
        case "SYSTEM": return L("system_default")
        case "DARK": return L("dark")
        default: return L("light")
        }
      }
    }
  }

  private var styleChoice: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: L("style"))
      Segmented(options: [false, true], selected: faded($minimal)) { $0 ? L("minimal") : L("cloudy") }
    }
  }

  /// A choice that changes the whole look, which fades over from the screen as it was.
  private func faded<T>(_ value: Binding<T>) -> Binding<T> {
    Binding(get: { value.wrappedValue }, set: { new in
      ThemeFade.beforeChange()
      value.wrappedValue = new
    })
  }

  /// The app's language, named in itself.
  private var currentLanguage: String {
    let id = Bundle.main.preferredLocalizations.first ?? "en"
    return Locale(identifier: id).localizedString(forIdentifier: id)?.capitalized(with: Locale(identifier: id)) ?? id
  }
}

/// Theme beside Style, sharing the width 1.6 to 1 as Android's weights do, or one under the other
/// when narrower than 440 (side by side cut "System default" short on a phone).
private struct ThemeBesideStyle: SwiftUI.Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let w = proposal.width ?? 600
    return CGSize(width: w, height: frames(w, subviews).map(\.maxY).max() ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (view, f) in zip(subviews, frames(bounds.width, subviews)) {
      view.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
    }
  }

  private func frames(_ w: CGFloat, _ views: Subviews) -> [CGRect] {
    guard views.count == 2 else { return [] }
    func height(_ v: LayoutSubview, _ width: CGFloat) -> CGFloat { v.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    if w < 440 {
      let top = height(views[0], w)
      return [CGRect(x: 0, y: 0, width: w, height: top), CGRect(x: 0, y: top + 14, width: w, height: height(views[1], w))]
    }
    let first = (w - 16) * 1.6 / 2.6
    let second = w - 16 - first
    return [CGRect(x: 0, y: 0, width: first, height: height(views[0], first)), CGRect(x: first + 16, y: 0, width: second, height: height(views[1], second))]
  }
}

/// A tiny library in [p]'s colours (Android's `ThemePreview`): sky and a cloud above, a notebook
/// card with a spine and two lines, and the + button.
struct ThemePreview: View {
  var p: TaliColors

  var body: some View {
    Canvas { ctx, size in
      let w = size.width
      let h = size.height
      ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(p.background))
      let skyRect = CGRect(x: 0, y: 0, width: w, height: h * 0.55)
      ctx.fill(Path(skyRect), with: .linearGradient(Gradient(colors: [p.skyFrom, p.skyTo]), startPoint: .zero, endPoint: CGPoint(x: w, y: h * 0.5)))
      ctx.fill(
        Path(skyRect),
        with: .linearGradient(Gradient(colors: [.clear, p.background]), startPoint: CGPoint(x: 0, y: h * 0.25), endPoint: CGPoint(x: 0, y: h * 0.55)))
      let cx = w * 0.3
      let cy = h * 0.27
      let puffs: [(CGFloat, CGFloat, CGFloat)] = [(cx - 7, cy + 2, 7), (cx + 2, cy - 1, 9.5), (cx + 11, cy + 3, 6.5)]
      for (x, y, r) in puffs {
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(p.skyCloudTop))
      }
      ctx.fill(Path(roundedRect: CGRect(x: cx - 13, y: cy + 2, width: 30, height: 7), cornerRadius: 4), with: .color(p.skyCloudTop))
      let card = CGRect(x: w * 0.12, y: h * 0.5, width: w * 0.5, height: h * 0.38)
      ctx.fill(Path(roundedRect: card.offsetBy(dx: 0, dy: 2), cornerRadius: 6), with: .color(p.glow.opacity(0.12)))
      ctx.fill(Path(roundedRect: card, cornerRadius: 6), with: .color(p.surface))
      ctx.fill(Path(roundedRect: CGRect(x: card.minX, y: card.minY, width: 4, height: card.height), cornerRadius: 2), with: .color(p.lilacDeep))
      var l1 = Path()
      l1.move(to: CGPoint(x: card.minX + 9, y: card.minY + card.height * 0.38))
      l1.addLine(to: CGPoint(x: card.minX + card.width * 0.8, y: card.minY + card.height * 0.38))
      ctx.stroke(l1, with: .color(p.inkFaint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
      var l2 = Path()
      l2.move(to: CGPoint(x: card.minX + 9, y: card.minY + card.height * 0.68))
      l2.addLine(to: CGPoint(x: card.minX + card.width * 0.55, y: card.minY + card.height * 0.68))
      ctx.stroke(l2, with: .color(p.blue), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
      let b: CGFloat = 18
      let bo = CGRect(x: w * 0.86 - b, y: h * 0.62, width: b, height: b)
      ctx.fill(
        Path(roundedRect: bo, cornerRadius: 6),
        with: .linearGradient(Gradient(colors: [p.accent, p.blue]), startPoint: bo.origin, endPoint: CGPoint(x: bo.maxX, y: bo.maxY)))
      var plus = Path()
      plus.move(to: CGPoint(x: bo.midX - 4.5, y: bo.midY))
      plus.addLine(to: CGPoint(x: bo.midX + 4.5, y: bo.midY))
      plus.move(to: CGPoint(x: bo.midX, y: bo.midY - 4.5))
      plus.addLine(to: CGPoint(x: bo.midX, y: bo.midY + 4.5))
      ctx.stroke(plus, with: .color(p.onAccent), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }
    .clipShape(RoundedRectangle(cornerRadius: 15))
    .overlay(RoundedRectangle(cornerRadius: 15).stroke(p.line, lineWidth: 1))
  }
}
