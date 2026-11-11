import SwiftUI
import TaliCore

/// The Shapes and Fill tools' settings, app-wide, under the names Android's `AppSettings` uses.
/// Views watch the same keys with `@AppStorage`; the canvas reads them here when it needs them.
@MainActor
enum ShapeSettings {
  enum Key {
    static let lastShape = "lastShape"
    static let customShapes = "customShapes"
    static let starredPacks = "starredPacks"
    static let style = "shapeStyle"
    static let followsPen = "shapeFollowsPen"
    static let holdToShape = "holdToShape"
    static let snapShapes = "snapShapes"
    static let fillColor = "fillColor"
    static let fillNone = "fillNone"
    static let fillOpacity = "fillOpacity"
  }

  static let defaultFill = 0xFF9D_B8F5
  static let defaultFillOpacity = 0.7

  private static var store: UserDefaults { .standard }

  // MARK: Her saved shapes

  static func shapes(from json: String) -> [CustomShape] {
    guard let list = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else { return [] }
    return list.compactMap(CustomShape.init(json:))
  }

  static func json(of shapes: [CustomShape]) -> String {
    (try? JSONSerialization.data(withJSONObject: shapes.map(\.json))).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
  }

  static var customShapes: [CustomShape] {
    get { shapes(from: store.string(forKey: Key.customShapes) ?? "[]") }
    set { store.set(json(of: newValue), forKey: Key.customShapes) }
  }

  // MARK: Starred subjects

  static func starred(from list: String) -> Set<String> { Set(list.split(separator: ",").map(String.init)) }

  static func list(of starred: Set<String>) -> String { ShapePacks.all.map(\.id).filter(starred.contains).joined(separator: ",") }

  /// The starred subjects' shapes, which hold-to-shape matches as well as hers.
  static var starredShapes: [PackShape] {
    let ids = starred(from: store.string(forKey: Key.starredPacks) ?? "")
    return ShapePacks.all.filter { ids.contains($0.id) }.flatMap(\.shapes)
  }

  // MARK: The Shapes tool's style

  static func style(from json: String) -> ShapeLook? {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]).flatMap(ShapeLook.init(json:))
  }

  static func json(of style: ShapeLook) -> String {
    (try? JSONSerialization.data(withJSONObject: style.json)).map { String(decoding: $0, as: UTF8.self) } ?? ""
  }

  /// Its own style, which stays as she set it whatever pen she picks (before she sets one: the
  /// first pen's starting colour and size).
  static func own(_ json: String) -> ShapeLook {
    style(from: json) ?? ShapeLook(color: Int32(bitPattern: PenSlot.defaultColors[0]), size: 2.4)
  }

  /// The pen the Shapes tool follows: the one in use, unless that's a highlighter, then the first writing pen.
  static func shapeSlot(active: PenSlot?, pens: [PenSlot]) -> PenSlot {
    let active = active ?? pens.first ?? PenSlot.defaults[0]
    return active.type != .HIGHLIGHTER ? active : pens.first { $0.type != .HIGHLIGHTER } ?? active
  }

  /// How the Shapes tool draws: its own style, or with Like the pen that pen's colour and size.
  static func look(own: ShapeLook, followsPen: Bool, pen: PenSlot) -> ShapeLook {
    // Pens here have no line style of their own yet, so a shape that follows one is solid.
    followsPen ? own.following(color: pen.color, size: pen.size, line: "SOLID") : own
  }

  static func look(active: PenSlot?, pens: [PenSlot]) -> ShapeLook {
    look(own: own(store.string(forKey: Key.style) ?? ""), followsPen: store.bool(forKey: Key.followsPen), pen: shapeSlot(active: active, pens: pens))
  }

  static var holdToShape: Bool { store.object(forKey: Key.holdToShape) as? Bool ?? true }

  // MARK: The fill tool

  /// The fill tool's colour with its opacity, or nil when it takes fills away.
  static var fillArgb: Int32? {
    if store.bool(forKey: Key.fillNone) { return nil }
    let colour = Int32(truncatingIfNeeded: store.object(forKey: Key.fillColor) as? Int ?? defaultFill)
    return FillColour.argb(colour, opacity: Float(store.object(forKey: Key.fillOpacity) as? Double ?? defaultFillOpacity))
  }
}

func lineStyleName(_ line: String) -> String { L("line_style_" + line.lowercased()) }

/// A subject's name in the app's language (Android's `ShapePack.title`).
func subjectName(_ pack: ShapePack) -> String { L("subject_" + pack.id.replacingOccurrences(of: "-", with: "_")) }

/// A subject shape's name in the app's language; a built-in symbol uses its own (Android's `PackShape.title`).
func subjectShapeName(_ shape: PackShape) -> String {
  shape.kind.map(shapeName) ?? L("subject_shape_" + shape.id.replacingOccurrences(of: "-", with: "_"))
}
