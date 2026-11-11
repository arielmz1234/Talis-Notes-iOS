import Foundation
import Testing
@testable import TaliCore

struct SavedColoursTests {
  let palette: [UInt32] = [0xFF00_0001, 0xFF00_0002, 0xFF00_0003, 0xFF00_0004]

  @Test func aNewColourGoesLastAndASavedOneIsNotSavedTwice() {
    #expect(SavedColours.saving(0xFF00_0009, in: palette) == palette + [0xFF00_0009])
    #expect(SavedColours.saving(0xFF00_0002, in: palette) == palette)
  }

  @Test func removingTakesJustThatColour() {
    #expect(SavedColours.removing(0xFF00_0002, from: palette) == [0xFF00_0001, 0xFF00_0003, 0xFF00_0004])
  }

  @Test func aNewOrderIsKeptOnlyWhenItHoldsTheSameColours() {
    let order: [UInt32] = [0xFF00_0004, 0xFF00_0001, 0xFF00_0002, 0xFF00_0003]
    #expect(SavedColours.reordered(palette, to: order) == order)
    #expect(SavedColours.reordered(palette, to: [0xFF00_0004, 0xFF00_0001]) == palette)
    #expect(SavedColours.reordered(palette, to: [0xFF00_0004, 0xFF00_0001, 0xFF00_0002, 0xFF00_0009]) == palette)
  }

  @Test func aDraggedColourTakesThePlaceOfTheOneUnderTheFinger() {
    // Forwards it lands after the one it passed; backwards, before it.
    #expect(SavedColours.moving(0xFF00_0001, onto: 0xFF00_0003, in: palette) == [0xFF00_0002, 0xFF00_0003, 0xFF00_0001, 0xFF00_0004])
    #expect(SavedColours.moving(0xFF00_0004, onto: 0xFF00_0002, in: palette) == [0xFF00_0001, 0xFF00_0004, 0xFF00_0002, 0xFF00_0003])
    #expect(SavedColours.moving(0xFF00_0001, onto: 0xFF00_0004, in: palette) == [0xFF00_0002, 0xFF00_0003, 0xFF00_0004, 0xFF00_0001])
    #expect(SavedColours.moving(0xFF00_0001, onto: 0xFF00_0001, in: palette) == palette)
  }

  @Test func coloursWrapIntoRowsWithADividerAfterTheToolbarOnes() {
    let layout = SavedColours.Layout(count: 11, inToolbar: 3, width: 356)
    #expect(layout.colors[0] == Pt(0, 0))
    #expect(layout.colors[2] == Pt(80, 0))
    #expect(layout.divider == Pt(120, 0))
    #expect(layout.colors[3] == Pt(130, 0))
    #expect(layout.colors[7] == Pt(290, 0))
    #expect(layout.colors[8] == Pt(0, 40))
    #expect(layout.add == Pt(120, 40))
    #expect(layout.height == 78)
  }

  @Test func thereIsNoDividerWhenNoneOrAllAreInTheToolbar() {
    #expect(SavedColours.Layout(count: 6, inToolbar: 0, width: 356).divider == nil)
    #expect(SavedColours.Layout(count: 6, inToolbar: 6, width: 356).divider == nil)
    #expect(SavedColours.Layout(count: 6, inToolbar: 5, width: 356).divider != nil)
  }
}
