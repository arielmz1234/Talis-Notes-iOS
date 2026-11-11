import Foundation
import Observation
import TaliCore

/// Her papers and what she set on the paper cards, app-wide as on Android (`AppSettings.customPapers`,
/// `paperWeights`, `paperLooks`, `paperLineWeight`, `pageGuides`, `defaultCustomPaper`), kept under
/// those names in Android's JSON shape.
@MainActor @Observable
final class PaperSettings {
  static let shared = PaperSettings()

  private let store = UserDefaults.standard

  var customPapers: [CustomPaper] { didSet { save(customPapers, "customPapers") } }
  var weights: [String: Float] { didSet { save(weights, "paperWeights") } }
  var looks: [String: PaperLook] { didSet { save(looks, "paperLooks") } }
  /// The thickness papers without one of their own are drawn at.
  var lineWeight: Float { didSet { store.set(lineWeight, forKey: "paperLineWeight") } }
  /// Faint A4 page edges on an endless canvas.
  var pageGuides: Bool { didSet { store.set(pageGuides, forKey: "pageGuides") } }
  /// The paper new notebooks start with when it's one of hers.
  var defaultCustomPaper: String? { didSet { store.set(defaultCustomPaper, forKey: "defaultCustomPaper") } }

  private init() {
    let d = UserDefaults.standard
    // UI tests start with none of her papers, as they start with an empty library.
    let fresh = ProcessInfo.processInfo.arguments.contains("-uitest")
    func load<T: Decodable>(_ key: String) -> T? { fresh ? nil : d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    customPapers = load("customPapers") ?? []
    weights = load("paperWeights") ?? [:]
    looks = load("paperLooks") ?? [:]
    lineWeight = fresh ? 1 : d.object(forKey: "paperLineWeight") as? Float ?? 1
    pageGuides = !fresh && d.bool(forKey: "pageGuides")
    defaultCustomPaper = fresh ? nil : d.string(forKey: "defaultCustomPaper")
  }

  private func save<T: Encodable>(_ value: T, _ key: String) {
    if let d = try? JSONEncoder().encode(value) { store.set(d, forKey: key) }
  }

  func custom(_ id: String?) -> CustomPaper? { id.flatMap { id in customPapers.first { $0.id == id } } }

  func weight(_ style: PaperStyle, custom: CustomPaper?) -> Float { PaperWeight.of(style, custom: custom, weights: weights, fallback: lineWeight) }

  func spec(_ style: PaperStyle, custom: CustomPaper?, dark: Bool) -> PaperSpec {
    PaperSpec(style: style, dark: dark, custom: custom, look: custom == nil ? looks[style.rawValue] : nil, weight: CGFloat(weight(style, custom: custom)))
  }

  func setWeight(_ style: PaperStyle, _ w: Float) { weights[style.rawValue] = min(max(w, 0.5), 5) }

  /// Her colours for a built-in paper; none at all puts it back as it came.
  func setLook(_ style: PaperStyle, _ look: PaperLook) {
    if look.isEmpty { looks[style.rawValue] = nil } else { looks[style.rawValue] = look }
  }

  func add(_ p: CustomPaper) { customPapers.append(p) }

  func update(_ p: CustomPaper) { customPapers = customPapers.map { $0.id == p.id ? p : $0 } }

  /// Notebooks that used it show blank paper.
  func remove(_ id: String) {
    customPapers.removeAll { $0.id == id }
    if defaultCustomPaper == id { defaultCustomPaper = nil }
  }
}
