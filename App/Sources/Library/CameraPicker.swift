import SwiftUI
import UIKit

/// The + menu's Camera (Android's camera screen for + › Camera): the system camera, one photo, which
/// becomes a Picture item. iOS's camera sheet has its own Cancel, which is what Android's own camera
/// screen was built for, so the system one serves here.
struct CameraPicker: UIViewControllerRepresentable {
  var onPhoto: (UIImage) -> Void
  var onClose: () -> Void

  static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let c = UIImagePickerController()
    c.sourceType = .camera
    c.delegate = context.coordinator
    return c
  }

  func updateUIViewController(_ c: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraPicker
    init(_ parent: CameraPicker) { self.parent = parent }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
      parent.onClose()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onClose() }
  }
}
