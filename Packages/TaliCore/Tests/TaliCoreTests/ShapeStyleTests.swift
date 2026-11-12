import Foundation
import Testing
@testable import TaliCore

struct ShapeStyleTests {
  @Test func opacitiesGoIntoTheAlpha() {
    let s = ShapeStyle(color: Int32(bitPattern: 0xFF12_3456), size: 2, fill: Int32(bitPattern: 0xFFAB_CDEF), opacity: 0.5, fillOpacity: 0.2)
    #expect(UInt32(bitPattern: s.outlineArgb) == 0x7F12_3456)
    #expect(UInt32(bitPattern: s.fillArgb!) == 0x33AB_CDEF)
    #expect(ShapeStyle(color: 0, size: 2).fillArgb == nil)
  }

  @Test func opacityNeverGoesBelowTheMinimum() {
    let a = UInt32(bitPattern: ShapeStyle.withOpacity(Int32(bitPattern: 0xFF00_0000), 0)) >> 24
    #expect(a == 25)
  }

  @Test func followingThePenTakesItsColourSizeAndLineButKeepsTheFill() {
    let own = ShapeStyle(color: 1, size: 3, line: "DOTTED", fill: 7, opacity: 0.6, fillOpacity: 0.3)
    let l = ShapeStyle.look(own: own, followsPen: true, penColor: 0x00FF_0000, penSize: 20)
    #expect(UInt32(bitPattern: l.color) == 0xFFFF_0000)
    #expect(l.size == ShapeStyle.maxSize)
    #expect(l.line == "SOLID")
    #expect(l.fill == 7 && l.opacity == 0.6 && l.fillOpacity == 0.3)
    #expect(ShapeStyle.look(own: own, followsPen: false, penColor: 5, penSize: 1) == own)
  }

  @Test func readsAndroidSettingsJson() throws {
    let json = #"{"color":-16777216,"size":2.4,"fill":-65536}"#.data(using: .utf8)!
    let s = try JSONDecoder().decode(ShapeStyle.self, from: json)
    #expect(s.line == "SOLID" && s.opacity == 1 && s.fillOpacity == 0.5)
    #expect(s.fill == -65536)
  }
}
