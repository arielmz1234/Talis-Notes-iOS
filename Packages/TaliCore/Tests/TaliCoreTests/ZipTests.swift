import Foundation
import Testing
@testable import TaliCore

struct ZipTests {
  /// Written by Python's zipfile (deflated), like a backup from another tool.
  static let pythonZip = Data(
    hex:
      "504b03041400000008006e926a5d293e32b932000000320000000d0000006d616e69666573742e6a736f6eab564acb2fca4d2c51b232d4514a2e4a4d2c494d01b2cd2d0d2d8ccd8d2d8d4d4c8d7494f2f24b5293f2f3b38b95ac2c6b01504b03041400000008006e926a5dc14842590c0000002c0100000c000000696d616765732f612e747874cb48cdc9c957c81825892001504b010214001400000008006e926a5d293e32b932000000320000000d00000000000000000000008001000000006d616e69666573742e6a736f6e504b010214001400000008006e926a5dc14842590c0000002c0100000c000000000000000000000080015d000000696d616765732f612e747874504b0506000000000200020075000000930000000000"
  )

  @Test func readsAZipFromElsewhere() throws {
    let z = try Zip.Reader(Self.pythonZip)
    #expect(z.entries.map(\.name) == ["manifest.json", "images/a.txt"])
    #expect(String(decoding: try z.read("manifest.json")!, as: UTF8.self) == #"{"format":1,"created":1791837393452,"notebooks":9}"#)
    #expect(try z.read("images/a.txt") == Data(String(repeating: "hello ", count: 50).utf8))
  }

  @Test func readsWhatItWrites() throws {
    var w = Zip.Writer()
    let big = Data((0..<20_000).map { UInt8($0 % 7) })
    w.add("notes.db", big)
    w.add("images/x.jpg", Data([1, 2, 3]))
    w.add("thumbs/", Data(), deflate: false)
    let z = try Zip.Reader(w.finished())
    #expect(try z.read("notes.db") == big)
    #expect(try z.read("images/x.jpg") == Data([1, 2, 3]))
    #expect(z.entry("thumbs/")?.isDirectory == true)
  }

  @Test func notAZip() {
    #expect(throws: (any Error).self) { try Zip.Reader(Data("hello there, not a zip at all".utf8)) }
  }
}
