import Foundation

/// What a double-tap or a squeeze of Apple Pencil does: the counterpart of the S Pen's side button,
/// which erases while held. It follows what she chose for the gesture in the system's Apple Pencil
/// settings, so it does here what it does in other apps.
public enum PencilGesture {
  public enum Preference: Sendable {
    case ignore
    case switchEraser
    case switchPrevious
    /// Any of the system's choices that show a palette of colours or pens.
    case showPalette
    /// Runs a shortcut of her own, which the system does by itself.
    case systemShortcut
  }

  public enum Action: Equatable, Sendable {
    case none
    case eraser
    /// Back to the tool in use before this one.
    case previousTool
    case penSettings
  }

  public static func action(for preference: Preference, erasing: Bool) -> Action {
    switch preference {
    case .ignore, .systemShortcut: .none
    case .switchEraser: erasing ? .previousTool : .eraser
    case .switchPrevious: .previousTool
    case .showPalette: .penSettings
    }
  }
}
