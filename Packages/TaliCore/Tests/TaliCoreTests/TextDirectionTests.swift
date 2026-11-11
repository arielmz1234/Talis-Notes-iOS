import Testing
@testable import TaliCore

/// Typed text runs the way Android's FIRSTSTRONG_LTR lays it out, whatever the app's language.
struct TextDirectionTests {
  @Test func theFirstLetterDecides() {
    #expect(!TextDirection.isRightToLeft("Sum of moments = 0"))
    #expect(TextDirection.isRightToLeft("סכום המומנטים = 0"))
    #expect(TextDirection.isRightToLeft("مجموع العزوم"))
    #expect(!TextDirection.isRightToLeft("R = 12 kN, כוח"))
    #expect(TextDirection.isRightToLeft("12 = כוח R"))
  }

  @Test func withoutLettersItRunsLeftToRight() {
    #expect(!TextDirection.isRightToLeft("12 + 7 = 19"))
    #expect(!TextDirection.isRightToLeft(""))
  }

  @Test func eachParagraphHasItsOwnDirection() {
    let text = "Statics\nסטטיקה\n\n42"
    let p = TextDirection.paragraphs(text)
    #expect(p.map { String(text[$0.range]) } == ["Statics", "סטטיקה", "", "42"])
    #expect(p.map(\.rightToLeft) == [false, true, false, false])
  }
}
