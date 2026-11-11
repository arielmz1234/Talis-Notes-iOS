/// Which way a paragraph of typed text runs: Android lays text boxes out with
/// `TextDirectionHeuristics.FIRSTSTRONG_LTR`, so the first letter that has a direction decides
/// (Hebrew or Arabic: right to left), and a paragraph without one (digits, signs) runs left to right.
public enum TextDirection {
  public static func isRightToLeft<S: StringProtocol>(_ paragraph: S) -> Bool {
    for s in paragraph.unicodeScalars {
      if rightToLeft(s) { return true }
      if s.properties.isAlphabetic { return false }
    }
    return false
  }

  /// The paragraphs of [text] (split at line breaks, as Android's layout splits them) with their direction.
  public static func paragraphs(_ text: String) -> [(range: Range<String.Index>, rightToLeft: Bool)] {
    var out: [(Range<String.Index>, Bool)] = []
    var start = text.startIndex
    while true {
      let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
      out.append((start..<end, isRightToLeft(text[start..<end])))
      guard end < text.endIndex else { break }
      start = text.index(after: end)
    }
    return out
  }

  /// Hebrew, Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic and their presentation forms.
  private static func rightToLeft(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: return s.properties.isAlphabetic
    default: return false
    }
  }
}
