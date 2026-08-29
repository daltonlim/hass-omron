import Foundation

struct BPCategory: Equatable {
  enum Tone: String {
    case normal, elevated, stage1, stage2, crisis
  }

  let label: String
  let rating: String
  let tone: Tone

  static func rate(sys: Int, dia: Int) -> BPCategory {
    let label: String
    let tone: Tone
    if sys > 180 || dia > 120 {
      label = "Hypertensive crisis"
      tone = .crisis
    } else if sys >= 140 || dia >= 90 {
      label = "Hypertension stage 2"
      tone = .stage2
    } else if sys >= 130 || dia >= 80 {
      label = "Hypertension stage 1"
      tone = .stage1
    } else if sys >= 120 && dia < 80 {
      label = "Elevated"
      tone = .elevated
    } else {
      label = "Normal"
      tone = .normal
    }
    return BPCategory(label: label, rating: label == "Normal" ? "Good" : "Bad", tone: tone)
  }
}

struct BPReading: Identifiable, Codable, Equatable {
  var id: String { "\(user)-\(slot)-\(isoDate)-\(sys)-\(dia)-\(bpm)" }
  var user: Int
  var slot: Int
  var sys: Int
  var dia: Int
  var bpm: Int
  var ihb: Int
  var mov: Int
  var cuff: Int
  var battery: Int
  var datetime: Date?

  var isoDate: String {
    datetime?.ISO8601Format() ?? ""
  }

  var category: BPCategory { BPCategory.rate(sys: sys, dia: dia) }

  var flags: String {
    var bits: [String] = []
    if mov != 0 { bits.append("movement") }
    if ihb != 0 { bits.append("irregular") }
    if cuff != 0 { bits.append("cuff") }
    if battery != 0 { bits.append("battery") }
    return bits.isEmpty ? "—" : bits.joined(separator: ", ")
  }
}
