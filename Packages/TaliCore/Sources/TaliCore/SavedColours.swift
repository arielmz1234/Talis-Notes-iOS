import Foundation

/// Her saved colours, in her order (Android's `savedColors` and `highlighterColors`, edited through
/// `saveColor`, `removeColor` and `reorderColors`). The first few sit in the toolbar beside the pens.
public enum SavedColours {
  public static func saving(_ color: UInt32, in colors: [UInt32]) -> [UInt32] {
    colors.contains(color) ? colors : colors + [color]
  }

  public static func removing(_ color: UInt32, from colors: [UInt32]) -> [UInt32] {
    colors.filter { $0 != color }
  }

  /// [order] when it holds the same colours; otherwise nothing changes (the palette changed under the drag).
  public static func reordered(_ colors: [UInt32], to order: [UInt32]) -> [UInt32] {
    Set(order) == Set(colors) && order.count == colors.count ? order : colors
  }

  /// A colour being dragged takes the place of the one the finger is over; the rest close up.
  public static func moving(_ color: UInt32, onto over: UInt32, in order: [UInt32]) -> [UInt32] {
    guard color != over, let at = order.firstIndex(of: over), order.contains(color) else { return order }
    var list = order.filter { $0 != color }
    list.insert(color, at: min(at, list.count))
    return list
  }

  /// Where each colour sits when they're laid out in rows [width] wide, with a narrow divider after
  /// the last toolbar colour and an "add" button at the end (Android's `ReorderableColors`).
  public struct Layout: Equatable, Sendable {
    public static let dot: Float = 38
    public static let gap: Float = 2
    public static let dividerWidth: Float = 8

    /// Top-left corners, one per colour, then the add button's.
    public var colors: [Pt]
    public var divider: Pt?
    public var add: Pt
    public var height: Float

    public init(count: Int, inToolbar: Int, width: Float) {
      var x: Float = 0, y: Float = 0
      var spots: [Pt] = []
      var dividerAt: Pt?
      func place(_ w: Float) -> Pt {
        if x > 0, x + w > width {
          x = 0
          y += Layout.dot + Layout.gap
        }
        let p = Pt(x, y)
        x += w + Layout.gap
        return p
      }
      for i in 0..<count {
        spots.append(place(Layout.dot))
        if i == inToolbar - 1, i < count - 1 { dividerAt = place(Layout.dividerWidth) }
      }
      colors = spots
      divider = dividerAt
      add = place(Layout.dot)
      height = y + Layout.dot
    }
  }
}
