import Foundation
import Testing
@testable import TaliCore

/// The Android app's stroke storage. The fixture is a real fineliner stroke the Android app wrote
/// (a backup's notes.db, item bounds 64.76, 46.87 – 80.08, 55.35), decoded independently in Python.
struct InkCodecTests {
  static let androidStroke = Data(
    hex:
      "1f8b08000000000000ffe352e2129bc53f9f7937cb52b6e98cdf58de705ce27bc7d7c777814df4f9a7006b59fda5cd4e4240350d0ecb99fe32dfe69eccff997731c70dc6834ccb59f733892e703c6c251b63e6e024a5c625cff0e03ad3854e107a708b11482e98c9f461051384012445f79ab7992a8970f1363830c0c07f7b510686064b2d212e6e060410bdcd7fd2d248988ba7410055d0ca82d975e68b1d36be200100c94cf9f7bb000000"
  )

  @Test func readsAnAndroidStroke() throws {
    let s = try InkCodec.decode(Self.androidStroke)
    #expect(s.points.count == 11)
    #expect(s.tool == .stylus)
    let first = s.points[0], last = s.points[10]
    #expect(abs(first.x - 68.9248) < 0.001)
    #expect(abs(first.y - 54.1548) < 0.001)
    #expect(abs(last.x - 78.8819) < 0.001)
    #expect(abs(last.y - 48.0531) < 0.001)
    #expect(abs(s.points[1].t - 0.022) < 0.0005)
    #expect(abs(last.t - 0.176) < 0.0005)
    #expect(first.pressure == 1)
    #expect(last.pressure == 0)
    #expect(abs((first.orientation ?? 0) - 1.5708) < 0.001)
    #expect(abs((s.strokeUnitLength ?? 0) - 0.022571849) < 1e-6)
    // Every sample lies inside the bounds the Android app stored for the item.
    let r = Rect(64.76, 46.87, 80.09, 55.36)
    #expect(s.points.allSatisfy { r.contains(Pt($0.x, $0.y)) })
  }

  @Test func roundTripsWhatItWrites() throws {
    let pts = (0..<200).map { i -> InkInput in
      let f = Float(i)
      return InkInput(x: 100 + f * 1.37, y: 2000 - f * 0.41, t: f / 240, pressure: 0.2 + 0.003 * f, tilt: 0.7, orientation: 2.1)
    }
    let s = InkInputs(points: pts, tool: .stylus, strokeUnitLength: 0.0225)
    let back = try InkCodec.decode(InkCodec.encode(s))
    #expect(back.points.count == 200)
    for (a, b) in zip(pts, back.points) {
      #expect(abs(a.x - b.x) < 0.003)
      #expect(abs(a.y - b.y) < 0.003)
      #expect(abs(a.t - b.t) < 0.00001)
      #expect(abs(a.pressure! - b.pressure!) < 0.0002)
      #expect(abs(a.tilt! - b.tilt!) < 0.0004)
      #expect(abs(a.orientation! - b.orientation!) < 0.0016)
    }
    #expect(back.strokeUnitLength == 0.0225)
  }

  @Test func reencodingAnAndroidStrokeKeepsIt() throws {
    let s = try InkCodec.decode(Self.androidStroke)
    let again = try InkCodec.decode(InkCodec.encode(s))
    for (a, b) in zip(s.points, again.points) {
      #expect(abs(a.x - b.x) < 0.003)
      #expect(abs(a.y - b.y) < 0.003)
    }
  }

  @Test func fingerStrokesHaveNoPressure() throws {
    let s = InkInputs(points: [InkInput(x: 1, y: 2, t: 0), InkInput(x: 3, y: 4, t: 0.01)], tool: .touch)
    let back = try InkCodec.decode(InkCodec.encode(s))
    #expect(back.points[1].pressure == nil)
    #expect(back.tool == .touch)
  }

  @Test func gzipRoundTrip() throws {
    let text = Data(String(repeating: "Tali's notes ", count: 500).utf8)
    #expect(try Gzip.decompress(Gzip.compress(text)) == text)
    #expect(CRC32.of(Data("123456789".utf8)) == 0xCBF4_3926)
  }
}

extension Data {
  init(hex: String) {
    var bytes: [UInt8] = []
    var it = hex.makeIterator()
    while let a = it.next(), let b = it.next() { bytes.append(UInt8(String([a, b]), radix: 16)!) }
    self.init(bytes)
  }
}
