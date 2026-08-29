import SwiftUI

enum Theme {
  static let paper = Color(red: 0.953, green: 0.933, blue: 0.894)
  static let card = Color(red: 1.0, green: 0.980, blue: 0.949)
  static let ink = Color(red: 0.102, green: 0.133, blue: 0.173)
  static let muted = Color(red: 0.361, green: 0.404, blue: 0.455)
  static let line = Color(red: 0.851, green: 0.816, blue: 0.761)
  static let sys = Color(red: 0.706, green: 0.137, blue: 0.094)
  static let dia = Color(red: 0.106, green: 0.420, blue: 0.400)
  static let pulse = Color(red: 0.541, green: 0.353, blue: 0.071)
  static let elevated = Color(red: 0.788, green: 0.635, blue: 0.153)
  static let stage1 = Color(red: 0.851, green: 0.467, blue: 0.024)
  static let stage2 = Color(red: 0.706, green: 0.137, blue: 0.094)
  static let crisis = Color(red: 0.420, green: 0.059, blue: 0.059)

  static func zone(_ tone: BPCategory.Tone) -> Color {
    switch tone {
    case .normal: return dia
    case .elevated: return elevated
    case .stage1: return stage1
    case .stage2: return stage2
    case .crisis: return crisis
    }
  }
}
