import Foundation
import Testing
@testable import TaliCore

struct PapersTests {
  @Test func readsAndroidsSettingsShape() throws {
    // kotlinx.serialization leaves defaults out: only what she changed is written.
    let json = #"[{"id":"ab12cd34","name":"Wide lines","pattern":"GRID","spacingMm":10.5,"lineColor":-4539718,"margin":true,"opacity":0.5},{"id":"p2","name":"Planner","image":"img-1.jpg","opacity":0.4,"lineWeight":2.0}]"#
    let papers = try JSONDecoder().decode([CustomPaper].self, from: Data(json.utf8))
    #expect(papers[0] == CustomPaper(id: "ab12cd34", name: "Wide lines", pattern: .GRID, spacingMm: 10.5, lineColor: -4_539_718, margin: true, opacity: 0.5))
    #expect(papers[0].paperColor == -1)
    #expect(papers[1].image == "img-1.jpg")
    #expect(papers[1].pattern == .LINES)
    #expect(papers[1].lineWeight == 2)
  }

  @Test func writesWhatAndroidReads() throws {
    let p = CustomPaper(id: "x", name: "Dots", pattern: .DOTS, lineColor: Int32(bitPattern: 0xFFB9_D2F6))
    let obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
    #expect(obj["pattern"] as? String == "DOTS")
    #expect((obj["lineColor"] as? NSNumber)?.int32Value == Int32(bitPattern: 0xFFB9_D2F6))
    #expect(obj["image"] == nil)
    #expect(try JSONDecoder().decode(CustomPaper.self, from: JSONEncoder().encode(p)) == p)
  }

  @Test func opacityScalesOnlyTheAlpha() {
    let half = CustomPaper(id: "a", name: "a", opacity: 0.5)
    #expect(UInt32(bitPattern: half.faded(Int32(bitPattern: 0xFFDA_DADA))) == 0x7FDA_DADA)
    let tooFaint = CustomPaper(id: "a", name: "a", opacity: 0.01)
    #expect(UInt32(bitPattern: tooFaint.faded(Int32(bitPattern: 0xFF00_0000))) == 0x2600_0000)
  }

  @Test func lineWeightComesFromThePapersOwnCard() {
    #expect(PaperWeight.of(.GRID, custom: nil, weights: ["GRID": 2], fallback: 1) == 2)
    #expect(PaperWeight.of(.LINES, custom: nil, weights: ["GRID": 2], fallback: 1.5) == 1.5)
    #expect(PaperWeight.of(.GRID, custom: CustomPaper(id: "a", name: "a", lineWeight: 3.5), weights: ["GRID": 2], fallback: 1) == 3.5)
    #expect(PaperWeight.of(.GRID, custom: CustomPaper(id: "a", name: "a"), weights: ["GRID": 2], fallback: 1) == 1)
    #expect(PaperWeight.nearest(2.4) == 2)
    #expect(PaperWeight.nearest(0.5) == 0.6)
  }

  @Test func herColoursApplyOnLightPaperOnly() {
    let look = PaperLook(line: Int32(bitPattern: 0xFFB9_D2F6), paper: Int32(bitPattern: 0xFFFF_F8E8))
    let light = PaperTones.of(dark: false, look: look)
    #expect(light.paper == 0xFFFF_F8E8)
    #expect(light.blueLine == 0xFFB9_D2F6)
    #expect(light.major == 0xFFB9_D2F6)
    #expect(light.minor == 0x72B9_D2F6)
    #expect(PaperTones.of(dark: true, look: look) == PaperTones.of(dark: true))
  }

  @Test func darkPaperFlipsDarkInksAndLiftsTheRest() {
    func flip(_ v: UInt32) -> UInt32 { UInt32(bitPattern: DarkInk.onDarkPaper(Int32(bitPattern: v))) }
    #expect(flip(0xFF00_0000) == 0xFFE6_E6E6)
    #expect(flip(0xFFFF_FFFF) == 0xFFE6_E6E6)
    #expect(flip(0xFF80_8080) == 0xFF9E_9E9E)
    #expect(flip(0xFFFF_0000) == 0xFFFF_3D3D)
    #expect(flip(0x8000_0000) == 0x80E6_E6E6)
  }
}
