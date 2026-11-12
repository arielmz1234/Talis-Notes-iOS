import SwiftUI
import TaliCore

/// Material's outlined folder icons, as Android draws them: a folder, the open one (a folder being
/// looked at), and a new folder with a plus. Fill with `eoFill`.
struct FolderGlyph: Shape {
  var open = false
  var plus = false

  func path(in rect: CGRect) -> Path {
    let data =
      plus
      ? "M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm0 12H4V6h5.17l2 2H20v10zm-8-4h2v2h2v-2h2v-2h-2v-2h-2v2h-2z"
      : open
        ? "M20 6h-8l-2-2H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm0 12H4V8h16v10z"
        : "M9.17 6l2 2H20v10H4V6h5.17M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"
    return SVGPath.parse(data).applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24).translatedBy(x: rect.minX, y: rect.minY))
  }
}

/// Just enough of SVG path data for Material icons: M, L, H, V, C and Z, absolute and relative.
enum SVGPath {
  static func parse(_ d: String) -> Path {
    var tokens: [String] = []
    var cur = ""
    for ch in d {
      if ch.isLetter {
        if !cur.isEmpty { tokens.append(cur) }
        tokens.append(String(ch))
        cur = ""
      } else if ch == "-" {
        if !cur.isEmpty && cur.last != "e" { tokens.append(cur) }
        cur = cur.last == "e" ? cur + "-" : "-"
      } else if ch == "." && cur.contains(".") {
        tokens.append(cur)
        cur = "."
      } else if ch == " " || ch == "," {
        if !cur.isEmpty { tokens.append(cur) }
        cur = ""
      } else {
        cur.append(ch)
      }
    }
    if !cur.isEmpty { tokens.append(cur) }
    var p = Path()
    var i = 0
    var cmd: Character = "M"
    var pt = CGPoint.zero
    var start = CGPoint.zero
    func num() -> CGFloat {
      defer { i += 1 }
      return CGFloat(Double(tokens[i]) ?? 0)
    }
    while i < tokens.count {
      if let c = tokens[i].first, c.isLetter {
        cmd = c
        i += 1
        if c == "z" || c == "Z" {
          p.closeSubpath()
          pt = start
          continue
        }
      }
      let rel = cmd.isLowercase
      let base = rel ? pt : .zero
      switch cmd.uppercased() {
      case "M":
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        p.move(to: pt)
        start = pt
        cmd = rel ? "l" : "L"
      case "L":
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        p.addLine(to: pt)
      case "H":
        pt.x = (rel ? pt.x : 0) + num()
        p.addLine(to: pt)
      case "V":
        pt.y = (rel ? pt.y : 0) + num()
        p.addLine(to: pt)
      case "C":
        let c1 = CGPoint(x: base.x + num(), y: base.y + num())
        let c2 = CGPoint(x: base.x + num(), y: base.y + num())
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        p.addCurve(to: pt, control1: c1, control2: c2)
      default:
        i += 1
      }
    }
    return p
  }
}

/// The soft gradient behind a selected folder, in that folder's own colour.
func folderWashColors(_ color: Color, dark: Bool) -> [Color] {
  dark ? [color.opacity(0.42), color.opacity(0.14)] : [mix(.white, color, 0.42), mix(.white, color, 0.14)]
}

func folderWash(_ color: Color, dark: Bool) -> LinearGradient {
  LinearGradient(colors: folderWashColors(color, dark: dark), startPoint: .leading, endPoint: .trailing)
}

/// "All notebooks › Civil ›" above a folder's name; each part goes back up to that level.
struct Breadcrumb: View {
  var path: [Folder]
  var onSelect: (String?) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      crumb(L("all_notebooks"), nil)
      ForEach(path) { crumb($0.name, $0.id) }
    }
  }

  private func crumb(_ label: String, _ id: String?) -> some View {
    HStack(spacing: 0) {
      Button { onSelect(id) } label: {
        Text(label).font(TaliType.labelLarge).foregroundStyle(c.accent).lineLimit(1)
          .padding(.horizontal, 4).padding(.vertical, 2)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain).contentShape(Rectangle())
      Image(systemName: "chevron.forward").font(.system(size: 11, weight: .semibold)).foregroundStyle(c.inkFaint).frame(width: 16, height: 16)
    }
  }
}

/// A folder's hold menu (Android's `FolderMenu`): a folder inside, rename, move, its colour, delete.
struct FolderMenu: View {
  var folder: Folder
  var onNewFolder: () -> Void
  var onRename: () -> Void
  var onMove: () -> Void
  var onRecolor: (UInt32) -> Void
  var onDelete: () -> Void

  var body: some View {
    Button(action: onNewFolder) { Label(L("new_folder_inside"), systemImage: "folder.badge.plus") }
    Button(action: onRename) { Label(L("rename"), systemImage: "pencil") }
    Button(action: onMove) { Label(L("move_to_2"), systemImage: "folder") }.accessibilityIdentifier("menu-move-folder")
    ColourPalette(current: folder.color, onPick: onRecolor)
    Divider()
    Button(role: .destructive, action: onDelete) { Label(L("delete_folder"), systemImage: "trash") }.accessibilityIdentifier("menu-delete-folder")
  }
}

/// The cover and folder colours in a hold menu: iOS's row of swatches (Android's `CoverSwatches` in
/// its dropdown).
struct ColourPalette: View {
  var current: UInt32
  var onPick: (UInt32) -> Void

  var body: some View {
    Picker(L("colour"), selection: Binding(get: { current }, set: onPick)) {
      ForEach(Covers.all, id: \.self) { col in
        Image(systemName: "circle.fill").tint(Color(argb: col)).tag(col)
      }
    }
    .pickerStyle(.palette)
  }
}

/// A folder inside the open folder (Android's `FolderTile`): a 76 pt row tinted with its colour,
/// its name and what it holds.
struct FolderTile: View {
  var folder: Folder
  var count: Int
  var inner: Int
  @Environment(\.tali) private var c

  var body: some View {
    let tint = Color(argb: folder.color)
    let notebooks = count == 1 ? L("t_1_notebook") : L("n_notebooks", count)
    let folders: String? = inner == 0 ? nil : (inner == 1 ? L("t_1_folder_2") : L("n_folders_2", inner))
    HStack(spacing: 12) {
      FolderGlyph().fill(tint, style: FillStyle(eoFill: true)).frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 0) {
        Text(folder.name).font(TaliType.titleMedium).foregroundStyle(c.ink).lineLimit(1)
        Text([notebooks, folders].compactMap { $0 }.joined(separator: " · ")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .frame(height: 76)
    .background(
      RoundedRectangle(cornerRadius: 18).fill(c.surface)
        .overlay(RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06)], startPoint: .leading, endPoint: .trailing)))
    )
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line, lineWidth: 1))
    .shadow(color: c.accent.opacity(0.16), radius: 8, y: 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("folder-\(folder.name)")
  }
}

/// The last tile among a folder's folders: a dashed outline with "New folder".
struct NewFolderTile: View {
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        FolderGlyph(plus: true).fill(c.inkMuted, style: FillStyle(eoFill: true)).frame(width: 26, height: 26)
        Text(L("new_folder")).font(TaliType.titleSmall).foregroundStyle(c.inkMuted)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .frame(height: 76)
      .overlay(RoundedRectangle(cornerRadius: 18).inset(by: 0.75).stroke(c.inkFaint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.97))
    .accessibilityIdentifier("new-folder-tile")
  }
}
