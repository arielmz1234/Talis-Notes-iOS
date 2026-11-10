import Foundation

/// One pen sample, as androidx.ink keeps them: position in world units, seconds since the stroke
/// began, and pressure (0...1), tilt (0...π/2) and orientation (0...2π) when the pen reports them.
public struct InkInput: Hashable, Sendable {
  public var x: Float
  public var y: Float
  public var t: Float
  public var pressure: Float?
  public var tilt: Float?
  public var orientation: Float?

  public init(x: Float, y: Float, t: Float, pressure: Float? = nil, tilt: Float? = nil, orientation: Float? = nil) {
    self.x = x
    self.y = y
    self.t = t
    self.pressure = pressure
    self.tilt = tilt
    self.orientation = orientation
  }
}

/// A stroke's inputs, as stored in an ink item's payload.
public struct InkInputs: Hashable, Sendable {
  public enum Tool: Int, Sendable { case unknown = 0, mouse = 1, touch = 2, stylus = 3 }

  public var points: [InkInput]
  public var tool: Tool
  /// World units per "stroke unit" (Android's `strokeUnitLengthCm`-style hint), kept as it was read.
  public var strokeUnitLength: Float?
  public var noiseSeed: Float?

  public init(points: [InkInput], tool: Tool = .stylus, strokeUnitLength: Float? = nil, noiseSeed: Float? = nil) {
    self.points = points
    self.tool = tool
    self.strokeUnitLength = strokeUnitLength
    self.noiseSeed = noiseSeed
  }

  public var bounds: Rect? { Rect.around(points.map { Pt($0.x, $0.y) }) }
}

/// androidx.ink's stroke storage (`StrokeInputBatch.encode` / `decode`): a gzip'd
/// `CodedStrokeInputBatch` protobuf. Fields 1-6 are numeric runs for x, y, elapsed seconds, pressure,
/// tilt and orientation; each run is (1) packed zigzag deltas, (2) scale, (3) offset, and value i is
/// offset + scale × (sum of the first i+1 deltas). Field 7 is the tool type, 8 the stroke unit
/// length, 9 the noise seed. Worked out from strokes the Android app wrote (see InkCodecTests).
public enum InkCodec {
  public enum Failure: Error { case notGzip, badProto, mismatched }

  // The scales the Android encoder uses for these channels; positions get a scale fitted to the stroke.
  static let timeScale: Float = 1e-6
  static let pressureScale: Float = 1.0 / 4096
  static let tiltScale: Float = (Float.pi / 2) / 4096
  static let orientationScale: Float = (2 * Float.pi) / 4096

  public static func decode(_ data: Data) throws -> InkInputs {
    try decodeProto(try Gzip.decompress(data))
  }

  public static func encode(_ inputs: InkInputs) -> Data {
    Gzip.compress(encodeProto(inputs))
  }

  // MARK: Protobuf

  struct Run {
    var deltas: [Int64] = []
    var scale: Float = 1
    var offset: Float = 0
    var values: [Float] {
      var acc: Int64 = 0
      return deltas.map {
        acc += $0
        return offset + scale * Float(acc)
      }
    }
  }

  static func decodeProto(_ b: Data) throws -> InkInputs {
    var r = ProtoReader(Array(b))
    var runs: [Int: Run] = [:]
    var tool = InkInputs.Tool.unknown
    var unit: Float?
    var seed: Float?
    while !r.atEnd {
      let (field, wire) = try r.key()
      switch (field, wire) {
      case (1...6, 2): runs[field] = try decodeRun(try r.bytes())
      case (7, 0): tool = InkInputs.Tool(rawValue: Int(try r.varint())) ?? .unknown
      case (8, 5): unit = try r.float()
      case (9, 5): seed = try r.float()
      default: try r.skip(wire)
      }
    }
    let xs = runs[1]?.values ?? [], ys = runs[2]?.values ?? [], ts = runs[3]?.values ?? []
    guard xs.count == ys.count, ts.isEmpty || ts.count == xs.count else { throw Failure.mismatched }
    func channel(_ i: Int) -> [Float]? {
      guard let v = runs[i]?.values, v.count == xs.count, !v.isEmpty else { return nil }
      return v
    }
    let p = channel(4), tl = channel(5), o = channel(6)
    let points = xs.indices.map { i in
      InkInput(x: xs[i], y: ys[i], t: ts.isEmpty ? 0 : ts[i], pressure: p?[i], tilt: tl?[i], orientation: o?[i])
    }
    return InkInputs(points: points, tool: tool, strokeUnitLength: unit, noiseSeed: seed)
  }

  static func decodeRun(_ b: [UInt8]) throws -> Run {
    var r = ProtoReader(b)
    var run = Run()
    while !r.atEnd {
      let (field, wire) = try r.key()
      switch (field, wire) {
      case (1, 2):
        var inner = ProtoReader(try r.bytes())
        while !inner.atEnd { run.deltas.append(zigzag(try inner.varint())) }
      case (1, 0): run.deltas.append(zigzag(try r.varint()))
      case (2, 5): run.scale = try r.float()
      case (3, 5): run.offset = try r.float()
      default: try r.skip(wire)
      }
    }
    return run
  }

  static func zigzag(_ v: UInt64) -> Int64 { Int64(bitPattern: v >> 1) ^ -Int64(bitPattern: v & 1) }
  static func unzigzag(_ v: Int64) -> UInt64 { UInt64(bitPattern: (v << 1) ^ (v >> 63)) }

  /// A run for [values] at [scale] (offset = the smallest value, so every sum stays small).
  static func encodeRun(_ values: [Float], scale: Float, offset: Float? = nil) -> [UInt8] {
    let off = offset ?? (values.min() ?? 0)
    var w = ProtoWriter()
    var packed = ProtoWriter()
    var prev: Int64 = 0
    for v in values {
      let q = Int64(((v - off) / scale).rounded())
      packed.varint(unzigzag(q - prev))
      prev = q
    }
    w.bytes(1, packed.out)
    w.float(2, scale)
    if off != 0 { w.float(3, off) }
    return w.out
  }

  static func encodeProto(_ s: InkInputs) -> Data {
    var w = ProtoWriter()
    let xs = s.points.map(\.x), ys = s.points.map(\.y)
    // Positions: about a 300th of a world unit, coarser only for huge strokes so sums stay in range.
    func posScale(_ v: [Float]) -> Float {
      let range = (v.max() ?? 0) - (v.min() ?? 0)
      return max(1.0 / 320, range / 1_000_000)
    }
    w.bytes(1, encodeRun(xs, scale: posScale(xs)))
    w.bytes(2, encodeRun(ys, scale: posScale(ys)))
    w.bytes(3, encodeRun(s.points.map(\.t), scale: timeScale, offset: 0))
    if s.points.allSatisfy({ $0.pressure != nil }), !s.points.isEmpty {
      w.bytes(4, encodeRun(s.points.map { min(max($0.pressure!, 0), 1) }, scale: pressureScale, offset: 0))
    }
    if s.points.allSatisfy({ $0.tilt != nil }), !s.points.isEmpty {
      w.bytes(5, encodeRun(s.points.map { min(max($0.tilt!, 0), .pi / 2) }, scale: tiltScale, offset: 0))
    }
    if s.points.allSatisfy({ $0.orientation != nil }), !s.points.isEmpty {
      w.bytes(6, encodeRun(s.points.map { min(max($0.orientation!, 0), 2 * .pi) }, scale: orientationScale, offset: 0))
    }
    w.varintField(7, UInt64(s.tool.rawValue))
    if let u = s.strokeUnitLength { w.float(8, u) }
    if let n = s.noiseSeed { w.float(9, n) }
    return Data(w.out)
  }
}

struct ProtoReader {
  let b: [UInt8]
  var i = 0
  init(_ b: [UInt8]) { self.b = b }
  var atEnd: Bool { i >= b.count }

  mutating func varint() throws -> UInt64 {
    var shift: UInt64 = 0
    var result: UInt64 = 0
    while true {
      guard i < b.count, shift < 64 else { throw InkCodec.Failure.badProto }
      let x = b[i]
      i += 1
      result |= UInt64(x & 0x7F) << shift
      if x < 0x80 { return result }
      shift += 7
    }
  }

  mutating func key() throws -> (Int, Int) {
    let k = try varint()
    return (Int(k >> 3), Int(k & 7))
  }

  mutating func bytes() throws -> [UInt8] {
    let n = Int(try varint())
    guard n >= 0, i + n <= b.count else { throw InkCodec.Failure.badProto }
    defer { i += n }
    return Array(b[i..<i + n])
  }

  mutating func float() throws -> Float {
    guard i + 4 <= b.count else { throw InkCodec.Failure.badProto }
    var bits: UInt32 = 0
    for k in (0..<4).reversed() { bits = (bits << 8) | UInt32(b[i + k]) }
    i += 4
    return Float(bitPattern: bits)
  }

  mutating func skip(_ wire: Int) throws {
    switch wire {
    case 0: _ = try varint()
    case 1: i += 8
    case 2: _ = try bytes()
    case 5: i += 4
    default: throw InkCodec.Failure.badProto
    }
    if i > b.count { throw InkCodec.Failure.badProto }
  }
}

struct ProtoWriter {
  var out: [UInt8] = []

  mutating func varint(_ v: UInt64) {
    var v = v
    while v >= 0x80 {
      out.append(UInt8(v & 0x7F) | 0x80)
      v >>= 7
    }
    out.append(UInt8(v))
  }

  mutating func key(_ field: Int, _ wire: Int) { varint(UInt64(field << 3 | wire)) }
  mutating func varintField(_ field: Int, _ v: UInt64) {
    key(field, 0)
    varint(v)
  }
  mutating func bytes(_ field: Int, _ b: [UInt8]) {
    key(field, 2)
    varint(UInt64(b.count))
    out += b
  }
  mutating func float(_ field: Int, _ f: Float) {
    key(field, 5)
    let bits = f.bitPattern
    out += [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
  }
}
