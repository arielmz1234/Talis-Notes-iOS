import PencilKit
import TaliCore
import UIKit

extension PencilGesture.Preference {
  /// What she chose for the gesture in the system's Apple Pencil settings.
  @MainActor init(_ action: UIPencilPreferredAction) {
    switch action {
    case .ignore: self = .ignore
    case .switchEraser: self = .switchEraser
    case .switchPrevious: self = .switchPrevious
    case .showColorPalette, .showInkAttributes: self = .showPalette
    default:
      if #available(iOS 17.5, *), action == .showContextualPalette {
        self = .showPalette
      } else if #available(iOS 17.5, *), action == .runSystemShortcut {
        self = .systemShortcut
      } else {
        self = .ignore
      }
    }
  }
}

/// Apple Pencil's double-tap and squeeze: the counterpart of the S Pen's side button.
extension NoteCanvas.Coordinator: UIPencilInteractionDelegate {
  func installPencilGestures(on v: PKCanvasView) {
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    v.addInteraction(interaction)
  }

  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    // From iOS 17.5 the tap comes through the method below; answering both would switch tools twice.
    if #available(iOS 17.5, *) { return }
    pencil(UIPencilInteraction.preferredTapAction)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
    pencil(UIPencilInteraction.preferredTapAction)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
    if squeeze.phase == .ended { pencil(UIPencilInteraction.preferredSqueezeAction) }
  }

  private func pencil(_ action: UIPencilPreferredAction) {
    guard !parent.viewOnly else { return }
    parent.onPencil(PencilGesture.Preference(action))
  }
}
