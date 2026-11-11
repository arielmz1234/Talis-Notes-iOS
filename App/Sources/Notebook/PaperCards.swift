import PhotosUI
import SwiftUI
import TaliCore

private let lineColors: [UInt32] = [0xFFDA_DADA, 0xFFB9_D2F6, 0xFFD2_C3EE, 0xFFBF_E3CF, 0xFFF4_C6D4, 0xFF8E_95A2]
private let paperColors: [UInt32] = [0xFFFF_FFFF, 0xFFFF_F8E8, 0xFFF4_EEFF, 0xFFEE_F5FF, 0xFFEF_F8F2, 0xFFF6_F1EA]
/// A4's shape, for the cards' page in miniature.
private let pageAspect: CGFloat = 1322 / 1871

/// A built-in paper's card (Android's `BuiltInPaperDialog`): its line and paper colours and its line
/// thickness. Changes show at once, on the page behind and in every notebook on this paper; Reset
/// puts its colours back.
struct BuiltInPaperCard: View {
  var style: PaperStyle
  var onDone: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    let papers = PaperSettings.shared
    let look = papers.looks[style.rawValue]
    let current = look ?? PaperLook()
    VStack(alignment: .leading, spacing: 0) {
      Text(paperName(style)).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 4)
      Text(L("changes_show_in_every_notebook_on")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 16)
      // The page beside its controls; on a phone, above them.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 20) {
          preview(width: 110, look: look)
          controls(current)
        }
        VStack(alignment: .leading, spacing: 16) {
          preview(width: 90, look: look).frame(maxWidth: .infinity)
          controls(current)
        }
      }
      Spacer().frame(height: 20)
      HStack(spacing: 10) {
        Spacer()
        if look != nil { Button(L("reset")) { papers.setLook(style, PaperLook()) }.buttonStyle(QuietButtonStyle()) }
        Button(L("done"), action: onDone).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("paper-card-done")
      }
    }
    .padding(28)
    .frame(maxWidth: 520)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
  }

  private func preview(width: CGFloat, look: PaperLook?) -> some View {
    PaperSwatch(style: style, look: look, weight: CGFloat(PaperSettings.shared.weight(style, custom: nil)))
      .frame(width: width, height: width / pageAspect)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.line, lineWidth: 1))
  }

  private func controls(_ current: PaperLook) -> some View {
    let papers = PaperSettings.shared
    return VStack(alignment: .leading, spacing: 8) {
      if style != .BLANK {
        colorRow(L("lines"), lineColors, selected: current.line.map { UInt32(bitPattern: $0) } ?? lineColors[0]) { col in
          papers.setLook(style, PaperLook(line: Int32(bitPattern: col), paper: current.paper))
        }
      }
      colorRow(L("paper"), paperColors, selected: current.paper.map { UInt32(bitPattern: $0) } ?? paperColors[0]) { col in
        papers.setLook(style, PaperLook(line: current.line, paper: Int32(bitPattern: col)))
      }
      if style != .BLANK {
        Text(L("line_thickness")).font(TaliType.labelMedium).foregroundStyle(c.inkMuted).padding(.top, 10)
        LineWeightChoice(weight: Binding(get: { papers.weight(style, custom: nil) }, set: { papers.setWeight(style, $0) }))
      }
    }
  }

  private func colorRow(_ label: String, _ colors: [UInt32], selected: UInt32, pick: @escaping (UInt32) -> Void) -> some View {
    HStack(spacing: 0) {
      SectionLabel(text: label).frame(width: 64, alignment: .leading)
      ForEach(colors, id: \.self) { col in ColorDot(color: Color(argb: col), selected: col == selected, size: 26) { pick(col) } }
    }
  }
}

/// Making or editing one of her papers (Android's `NewPaperDialog`): design a pattern (lines, grid or
/// dots at her spacing, colours and thickness, with an optional margin line), or use a picture such
/// as a planner page, which fills each A4 page. A page in miniature shows it as it will look.
struct NewPaperCard: View {
  var editing: CustomPaper?
  var onSave: (CustomPaper) -> Void
  var onCancel: () -> Void
  @Environment(\.tali) private var c
  @State private var picture: Bool
  @State private var draft: CustomPaper
  @State private var name: String
  @State private var picking = false
  @State private var item: PhotosPickerItem?
  @State private var loading = false
  @State private var failed = false

  init(editing: CustomPaper? = nil, onSave: @escaping (CustomPaper) -> Void, onCancel: @escaping () -> Void) {
    self.editing = editing
    self.onSave = onSave
    self.onCancel = onCancel
    _picture = State(initialValue: editing?.image != nil)
    _draft = State(initialValue: editing ?? CustomPaper(id: String(newId().prefix(8)), name: ""))
    _name = State(initialValue: editing?.name ?? "")
  }

  private var shown: CustomPaper {
    var s = draft
    if !picture { s.image = nil }
    return s
  }
  private var canSave: Bool { !picture || draft.image != nil }
  private let labelWidth: CGFloat = 84

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // The name beside the title; on a phone, under it.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 20) {
          title
          nameField.frame(minWidth: 240)
        }
        VStack(alignment: .leading, spacing: 10) {
          title
          nameField
        }
      }
      Spacer().frame(height: 14)
      Segmented(options: [false, true], selected: $picture) { $0 ? L("from_a_picture") : L("design_a_pattern") }
      Spacer().frame(height: 14)
      // The middle scrolls only on a screen too short for the card (Android's `CardBody`).
      ViewThatFits(in: .vertical) {
        middle
        ScrollView { middle }
      }
      Spacer().frame(height: 16)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          footnote.frame(maxWidth: .infinity, alignment: .leading)
          buttons
        }
        VStack(alignment: .trailing, spacing: 12) {
          footnote.frame(maxWidth: .infinity, alignment: .leading)
          buttons
        }
      }
    }
    .padding(28)
    .frame(maxWidth: 680)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
    .photosPicker(isPresented: $picking, selection: $item, matching: .images)
    .onChange(of: item) { _, picked in
      guard let picked else { return }
      item = nil
      loading = true
      failed = false
      Task {
        let file = await Self.importPicture(picked)
        loading = false
        if let file { draft.image = file } else { failed = true }
      }
    }
  }

  private var title: some View {
    Text(editing != nil ? L("edit_paper") : L("your_own_paper")).font(TaliType.titleLarge).foregroundStyle(c.ink).fixedSize()
  }

  private var nameField: some View {
    TextField(picture ? L("name_e_g_weekly_planner") : L("name_e_g_wide_lines"), text: $name)
      .font(TaliType.bodyLarge).foregroundStyle(c.ink)
      .padding(.horizontal, 14).frame(height: 44)
      .background(RoundedRectangle(cornerRadius: 14).fill(c.sunken.opacity(0.7)))
      .submitLabel(.done)
      .onSubmit(save)
  }

  private var footnote: some View {
    Text(editing != nil ? L("changes_show_in_every_notebook_that") : L("saved_with_your_papers_for_every"))
      .font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
  }

  private var buttons: some View {
    HStack(spacing: 10) {
      Button(L("cancel"), action: onCancel).buttonStyle(QuietButtonStyle())
      if canSave {
        Button(editing != nil ? L("save_changes") : L("save_paper"), action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("save-paper")
      } else {
        Button(L("choose_a_picture")) { picking = true }.buttonStyle(PrimaryButtonStyle())
      }
    }
  }

  /// The page in miniature beside the controls; on a phone, above them with the labels over theirs.
  private var middle: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 22) {
        preview(width: 140)
        controls(narrow: false)
      }
      VStack(alignment: .leading, spacing: 14) {
        preview(width: 100).frame(maxWidth: .infinity)
        controls(narrow: true)
      }
    }
  }

  private func preview(width: CGFloat) -> some View {
    Group {
      if picture && draft.image == nil {
        c.sunken.overlay(Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(c.inkFaint))
      } else {
        CustomPaperSwatch(paper: shown)
      }
    }
    .frame(width: width, height: width / pageAspect)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.line, lineWidth: 1))
  }

  private func controls(narrow: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if picture { pictureControls(narrow) } else { patternControls(narrow) }
    }
  }

  @ViewBuilder private func pictureControls(_ narrow: Bool) -> some View {
    Text(L("the_picture_fills_each_a4_page")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
    Spacer().frame(height: 12)
    Button(loading ? L("opening") : (draft.image == nil ? L("choose_a_picture") : L("choose_another_picture"))) { picking = true }
      .buttonStyle(QuietButtonStyle())
    if failed {
      Text(L("that_picture_couldn_t_be_opened")).font(TaliType.bodySmall).foregroundStyle(c.danger).padding(.top, 8)
    }
    if draft.image != nil {
      opacityRow(narrow).padding(.top, 10)
      Text(L("fainter_pictures_keep_your_writing_easy")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
    }
  }

  @ViewBuilder private func patternControls(_ narrow: Bool) -> some View {
    labelled(L("pattern"), narrow) {
      Segmented(options: [PaperStyle.LINES, .GRID, .DOTS, .BLANK], selected: $draft.pattern) { paperName($0) }
    }
    if draft.pattern != .BLANK {
      labelled(L("spacing"), narrow) {
        Slider(value: Binding(get: { draft.spacingMm }, set: { draft.spacingMm = (($0 * 2).rounded(.down)) / 2 }), in: 3...14).tint(c.accent)
        Text(L("n_mm", draft.spacingMm.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(draft.spacingMm))" : "\(draft.spacingMm)"))
          .font(TaliType.labelMedium).foregroundStyle(c.inkMuted).frame(width: 52, alignment: .leading).padding(.leading, 8)
      }
      opacityRow(narrow)
      labelled(L("thickness"), narrow) {
        LineWeightChoice(weight: Binding(get: { draft.lineWeight ?? PaperSettings.shared.lineWeight }, set: { draft.lineWeight = $0 }))
      }
      labelled(L("lines"), narrow) {
        ForEach(lineColors, id: \.self) { col in
          ColorDot(color: Color(argb: col), selected: UInt32(bitPattern: draft.lineColor) == col, size: 26) { draft.lineColor = Int32(bitPattern: col) }
        }
      }
    }
    labelled(L("paper"), narrow) {
      ForEach(paperColors, id: \.self) { col in
        ColorDot(color: Color(argb: col), selected: UInt32(bitPattern: draft.paperColor) == col, size: 26) { draft.paperColor = Int32(bitPattern: col) }
      }
    }
    ToggleRow(label: L("margin_line"), on: $draft.margin, detail: L("a_red_line_down_the_left"))
  }

  private func opacityRow(_ narrow: Bool) -> some View {
    labelled(L("opacity"), narrow) {
      Slider(value: Binding(get: { draft.opacity }, set: { draft.opacity = min(max(($0 * 20).rounded() / 20, 0.15), 1) }), in: 0.15...1).tint(c.accent)
      Text(L("n", Int((draft.opacity * 100).rounded()))).font(TaliType.labelMedium).foregroundStyle(c.inkMuted).frame(width: 52, alignment: .leading).padding(.leading, 8)
    }
  }

  @ViewBuilder private func labelled<V: View>(_ label: String, _ narrow: Bool, @ViewBuilder _ content: () -> V) -> some View {
    if narrow {
      VStack(alignment: .leading, spacing: 4) {
        SectionLabel(text: label)
        HStack(spacing: 0) { content() }
      }
      .padding(.vertical, 4)
    } else {
      HStack(spacing: 0) {
        SectionLabel(text: label).frame(width: labelWidth, alignment: .leading)
        content()
      }
      .frame(minHeight: 40)
    }
  }

  private func save() {
    guard canSave else { return }
    let fallback = picture ? L("my_picture") : L("my_n", paperName(draft.pattern).lowercased())
    var out = shown
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    out.name = trimmed.isEmpty ? fallback : trimmed
    onSave(out)
  }

  /// Copies a picked photo into the app's pictures, as a JPEG no larger than a page needs.
  private static func importPicture(_ item: PhotosPickerItem) async -> String? {
    guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
    return await Task.detached {
      guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
      let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true,
      ]
      guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary), let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.9) else { return nil }
      let name = "paper-\(UUID().uuidString.lowercased()).jpg"
      return (try? jpeg.write(to: AppFiles.folders.images.appendingPathComponent(name))) != nil ? name : nil
    }.value
  }
}
