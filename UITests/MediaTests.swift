import XCTest

/// Pictures, PDFs, voice memos, the camera and export.
@MainActor
final class MediaTests: ShotCase {

  private func openSeededPDF(_ app: XCUIApplication) -> Bool {
    let pdf = app.descendants(matching: .any)["notebook-Lecture slides"].firstMatch
    guard pdf.waitForExistence(timeout: 5) else { return false }
    pdf.tap()
    settle()
    return true
  }

  func testPdfOpens() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    XCTAssertTrue(openSeededPDF(app), "the seeded PDF is in the library")
    shot("m1-pdf")
  }
}
