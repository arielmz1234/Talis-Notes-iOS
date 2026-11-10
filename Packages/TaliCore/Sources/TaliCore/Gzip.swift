import Compression
import Foundation

/// Raw DEFLATE through Apple's Compression framework (`COMPRESSION_ZLIB` is raw deflate, no header),
/// and the gzip and zip wrappers around it.
public enum Deflate {
  public enum Failure: Error { case failed }

  public static func inflate(_ data: Data, expected: Int? = nil) throws -> Data {
    if data.isEmpty { return Data() }
    var capacity = max(expected ?? data.count * 4, 64)
    while true {
      var out = Data(count: capacity)
      let n = out.withUnsafeMutableBytes { dst in
        data.withUnsafeBytes { src in
          compression_decode_buffer(
            dst.bindMemory(to: UInt8.self).baseAddress!, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
      }
      if n == 0 { throw Failure.failed }
      // A full buffer may mean it was cut short: try again with more room.
      if n < capacity || expected == n { return out.prefix(n) }
      capacity *= 4
      if capacity > 1 << 31 { throw Failure.failed }
    }
  }

  public static func deflate(_ data: Data) -> Data {
    if data.isEmpty { return Data([0x03, 0x00]) }  // an empty final block
    let capacity = data.count + data.count / 2 + 1024
    var out = Data(count: capacity)
    let n = out.withUnsafeMutableBytes { dst in
      data.withUnsafeBytes { src in
        compression_encode_buffer(
          dst.bindMemory(to: UInt8.self).baseAddress!, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
      }
    }
    return out.prefix(n)
  }
}

public enum CRC32 {
  private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
    var c = UInt32(i)
    for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
  }

  public static func of(_ data: Data) -> UInt32 {
    var c: UInt32 = 0xFFFF_FFFF
    for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
    return c ^ 0xFFFF_FFFF
  }
}

public enum Gzip {
  public static func decompress(_ d: Data) throws -> Data {
    let b = [UInt8](d)
    guard b.count >= 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { throw InkCodec.Failure.notGzip }
    let flags = b[3]
    var i = 10
    if flags & 4 != 0 { i += 2 + (Int(b[i]) | (Int(b[i + 1]) << 8)) }  // extra
    if flags & 8 != 0 { while i < b.count && b[i] != 0 { i += 1 }; i += 1 }  // name
    if flags & 16 != 0 { while i < b.count && b[i] != 0 { i += 1 }; i += 1 }  // comment
    if flags & 2 != 0 { i += 2 }  // header crc
    guard i <= b.count - 8 else { throw InkCodec.Failure.notGzip }
    let n = b.count
    let size = Int(b[n - 4]) | Int(b[n - 3]) << 8 | Int(b[n - 2]) << 16 | Int(b[n - 1]) << 24
    return try Deflate.inflate(Data(b[i..<(n - 8)]), expected: size)
  }

  public static func compress(_ d: Data) -> Data {
    var out = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 0xFF])
    out += Deflate.deflate(d)
    let crc = CRC32.of(d), size = UInt32(truncatingIfNeeded: d.count)
    for v in [crc, size] { out += [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)] }
    return out
  }
}
