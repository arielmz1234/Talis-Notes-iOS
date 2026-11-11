import Foundation

/// A string from the catalog by its key, which is the Android resource name (so wording matches).
func L(_ key: String) -> String {
  String(localized: String.LocalizationValue(key))
}

/// A string with placeholders (%1$@, %2$@…), filled in with [args] shown as text.
func L(_ key: String, _ args: any CustomStringConvertible...) -> String {
  String(format: L(key), arguments: args.map { "\($0)" as NSString })
}

/// Names the app makes up are English in every language, as on Android (`english()`).
enum English {
  static let newNotebook = "New notebook"
  static let newFolder = "New folder"
  static let untitled = "Untitled"
  static let picture = "Picture"
  static func nPictures(_ n: Int) -> String { "\(n) pictures" }
}

func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

func newId() -> String { UUID().uuidString.lowercased() }
