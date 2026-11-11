import Foundation

extension ItemRow {
  /// The page it's on (Android's rule for moving pages: where the middle of its bounds is).
  public func page(in layout: Pages, count: Int) -> Int {
    min(max(layout.indexAt((t + b) / 2), 0), max(count - 1, 0))
  }

  /// Moved by [dx], [dy] world units, whatever kind of item it is. Everything else in it is kept.
  public func translated(_ dx: Float, _ dy: Float) -> ItemRow {
    var out = self
    out.l += dx
    out.r += dx
    out.t += dy
    out.b += dy
    switch kind {
    case 0:
      guard var inputs = try? InkCodec.decode(payload) else { return self }
      inputs.points = inputs.points.map {
        var p = $0
        p.x += dx
        p.y += dy
        return p
      }
      out.payload = InkCodec.encode(inputs)
    default:
      guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return self }
      out.payload = (try? JSONSerialization.data(withJSONObject: ItemRow.shift(obj, kind: kind, dx, dy))) ?? payload
    }
    return out
  }

  private static func num(_ f: Float) -> Double { Double("\(f)") ?? Double(f) }
  private static func float(_ v: Any?) -> Float { (v as? NSNumber)?.floatValue ?? 0 }

  /// The payload with its places moved: a picture's rect, text's and a memo's x/y, and every point
  /// of a shape (its "place" for a subject shape).
  private static func shift(_ o: [String: Any], kind: Int, _ dx: Float, _ dy: Float) -> [String: Any] {
    var o = o
    switch kind {
    case 2:
      if let r = o["rect"] as? [String: Any] {
        var m = r
        for (k, d) in [("left", dx), ("right", dx), ("top", dy), ("bottom", dy)] { m[k] = num(float(r[k]) + d) }
        o["rect"] = m
      }
    case 1:
      o = shape(o, dx, dy)
    default:
      if o["x"] != nil { o["x"] = num(float(o["x"]) + dx) }
      if o["y"] != nil { o["y"] = num(float(o["y"]) + dy) }
    }
    return o
  }

  private static func shape(_ o: [String: Any], _ dx: Float, _ dy: Float) -> [String: Any] {
    func point(_ v: Any) -> Any {
      guard let p = v as? [String: Any], p["type"] == nil, p.keys.contains("x"), p.keys.contains("y") else { return v }
      var q = p
      q["x"] = num(float(p["x"]) + dx)
      q["y"] = num(float(p["y"]) + dy)
      return q
    }
    var out = o
    for (k, v) in o {
      switch k {
      case "parts": out[k] = (v as? [Any])?.map { ($0 as? [String: Any]).map { shape($0, dx, dy) } ?? $0 } ?? v
      case "place":
        guard var m = v as? [String: Any] else { continue }
        m["tx"] = num(float(m["tx"]) + dx)
        m["ty"] = num(float(m["ty"]) + dy)
        out[k] = m
      default:
        if let list = v as? [Any] { out[k] = list.map(point) } else { out[k] = point(v) }
      }
    }
    return out
  }
}

/// Laying pages out again (Android's `NoteCanvasView.rearrangePages`).
public struct PageRearrangement: Equatable, Sendable {
  /// Items to delete (by id): everything on a page left out.
  public var removed: [String] = []
  /// Items to write: moved ones, and copies (new ids) of pages listed twice.
  public var written: [ItemRow] = []
  /// How many pages there are afterwards (one empty page stays when nothing's left).
  public var count: Int = 1
}

extension Pages {
  /// Pages laid out as [order] (old page numbers, top to bottom): a page left out is deleted with
  /// everything on it, a page listed again is copied with new ids and on top.
  public func rearranged(_ rows: [ItemRow], count: Int, order: [Int], newId: () -> String, nextZ: inout Int64) -> PageRearrangement {
    var out = PageRearrangement(count: max(order.count, 1))
    var byPage: [Int: [ItemRow]] = [:]
    for r in rows { byPage[r.page(in: self, count: count), default: []].append(r) }
    var placed = Set<Int>()
    for (j, p) in order.enumerated() {
      let dy = Float(j - p) * pitch
      let items = byPage[p] ?? []
      if placed.insert(p).inserted {
        if j != p { out.written += items.map { $0.translated(0, dy) } }
      } else {
        for item in items {
          var copy = item.translated(0, dy)
          copy.id = newId()
          nextZ += 1
          copy.z = nextZ
          out.written.append(copy)
        }
      }
    }
    for p in 0..<count where !placed.contains(p) { out.removed += (byPage[p] ?? []).map(\.id) }
    return out
  }

  /// How far everything moves when an endless canvas becomes pages (Android's `convertToPages`):
  /// writing left of, above or wider than the first page comes onto the pages, centred when it fits.
  public func shiftOntoPages(_ content: Rect?) -> Pt {
    let margin: Float = 60
    guard let c = content, c.left < 0 || c.right > width || c.top < 0 else { return .zero }
    let dx = c.width <= width - 2 * margin ? (width - c.width) / 2 - c.left : margin - c.left
    let dy = c.top < margin ? margin - c.top : 0
    return Pt(dx, dy)
  }
}
