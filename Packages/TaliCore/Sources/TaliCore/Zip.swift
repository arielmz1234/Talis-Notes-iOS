import Foundation

/// Reads and writes plain .zip files (stored or deflated entries, no zip64), enough for the Android
/// app's backups (`java.util.zip`: deflated entries, sizes in a data descriptor after each one; the
/// central directory has them too, so it's read from there).
public enum Zip {
  public enum Failure: Error { case notZip, unsupported(String), damaged }

  public struct Entry: Sendable {
    public let name: String
    let method: UInt16
    let compressedSize: Int
    let size: Int
    let crc: UInt32
    let localOffset: Int
    public var isDirectory: Bool { name.hasSuffix("/") }
  }

  public final class Reader: Sendable {
    let data: Data
    public let entries: [Entry]

    public init(_ data: Data) throws {
      self.data = data
      let b = [UInt8](data)
      func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
      func u32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
      guard b.count >= 22 else { throw Failure.notZip }
      // End of central directory: the last "PK\5\6" (a comment may follow it).
      var eocd = -1
      var i = b.count - 22
      while i >= max(0, b.count - 22 - 65_535) {
        if b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 5 && b[i + 3] == 6 {
          eocd = i
          break
        }
        i -= 1
      }
      guard eocd >= 0 else { throw Failure.notZip }
      let count = u16(eocd + 10)
      var p = u32(eocd + 16)
      var out: [Entry] = []
      for _ in 0..<count {
        guard p + 46 <= b.count, u32(p) == 0x0201_4B50 else { throw Failure.damaged }
        let method = UInt16(u16(p + 10))
        let crc = UInt32(u32(p + 16))
        let csize = u32(p + 20), size = u32(p + 24)
        let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
        let local = u32(p + 42)
        guard p + 46 + nameLen <= b.count else { throw Failure.damaged }
        let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
        if csize == 0xFFFF_FFFF || size == 0xFFFF_FFFF { throw Failure.unsupported("zip64") }
        out.append(Entry(name: name, method: method, compressedSize: csize, size: size, crc: crc, localOffset: local))
        p += 46 + nameLen + extraLen + commentLen
      }
      entries = out
    }

    public func entry(_ name: String) -> Entry? { entries.first { $0.name == name } }

    public func read(_ e: Entry) throws -> Data {
      let b = data
      let base = b.startIndex
      func u16(_ i: Int) -> Int { Int(b[base + i]) | Int(b[base + i + 1]) << 8 }
      let p = e.localOffset
      guard p + 30 <= b.count else { throw Failure.damaged }
      let start = p + 30 + u16(p + 26) + u16(p + 28)
      guard start + e.compressedSize <= b.count else { throw Failure.damaged }
      let raw = b.subdata(in: (base + start)..<(base + start + e.compressedSize))
      let out: Data
      switch e.method {
      case 0: out = raw
      case 8: out = try Deflate.inflate(raw, expected: e.size)
      default: throw Failure.unsupported("method \(e.method)")
      }
      guard out.count == e.size, CRC32.of(out) == e.crc else { throw Failure.damaged }
      return out
    }

    public func read(_ name: String) throws -> Data? { try entry(name).map(read) }
  }

  /// Builds a zip in memory, deflating each entry.
  public struct Writer {
    private var out = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    public mutating func add(_ name: String, _ content: Data, deflate: Bool = true) {
      let packed = deflate ? Deflate.deflate(content) : content
      let useDeflate = deflate && packed.count < content.count
      let body = useDeflate ? packed : content
      let crc = CRC32.of(content)
      let nameBytes = Data(name.utf8)
      let offset = out.count
      let (time, date) = Writer.dosNow()
      var local = Data()
      local.le32(0x0403_4B50)
      local.le16(20)
      local.le16(0x0800)  // names are UTF-8
      local.le16(useDeflate ? 8 : 0)
      local.le16(time)
      local.le16(date)
      local.le32(crc)
      local.le32(UInt32(body.count))
      local.le32(UInt32(content.count))
      local.le16(UInt16(nameBytes.count))
      local.le16(0)
      out += local + nameBytes + body
      var c = Data()
      c.le32(0x0201_4B50)
      c.le16(20)
      c.le16(20)
      c.le16(0x0800)
      c.le16(useDeflate ? 8 : 0)
      c.le16(time)
      c.le16(date)
      c.le32(crc)
      c.le32(UInt32(body.count))
      c.le32(UInt32(content.count))
      c.le16(UInt16(nameBytes.count))
      c.le16(0)
      c.le16(0)
      c.le16(0)
      c.le16(0)
      c.le32(0)
      c.le32(UInt32(offset))
      central += c + nameBytes
      count += 1
    }

    public func finished() -> Data {
      var end = Data()
      end.le32(0x0605_4B50)
      end.le16(0)
      end.le16(0)
      end.le16(UInt16(count))
      end.le16(UInt16(count))
      end.le32(UInt32(central.count))
      end.le32(UInt32(out.count))
      end.le16(0)
      return out + central + end
    }

    static func dosNow() -> (UInt16, UInt16) {
      let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
      let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
      let date = UInt16(max((c.year ?? 1980) - 1980, 0) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
      return (time, date)
    }
  }
}

extension Data {
  mutating func le16(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
  mutating func le16(_ v: Int) { le16(UInt16(truncatingIfNeeded: v)) }
  mutating func le32(_ v: UInt32) { append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)]) }
}
