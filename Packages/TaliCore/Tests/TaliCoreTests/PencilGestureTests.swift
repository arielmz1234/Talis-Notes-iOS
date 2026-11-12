import Testing
@testable import TaliCore

struct PencilGestureTests {
  @Test func switchingToTheEraserAndBack() {
    #expect(PencilGesture.action(for: .switchEraser, erasing: false) == .eraser)
    #expect(PencilGesture.action(for: .switchEraser, erasing: true) == .previousTool)
  }

  @Test func theOtherSystemChoicesAreFollowed() {
    for erasing in [false, true] {
      #expect(PencilGesture.action(for: .switchPrevious, erasing: erasing) == .previousTool)
      #expect(PencilGesture.action(for: .showPalette, erasing: erasing) == .penSettings)
      #expect(PencilGesture.action(for: .ignore, erasing: erasing) == .none)
      #expect(PencilGesture.action(for: .systemShortcut, erasing: erasing) == .none)
    }
  }
}
