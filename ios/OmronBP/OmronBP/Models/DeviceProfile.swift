import CoreBluetooth
import Foundation

enum UnlockMode: String, Codable {
  case token
  case classic
}

enum TimeLayout: String, Codable {
  case modernOffset8
  case classicMixed
}

enum RecordParserKind: String, Codable {
  case vital14
  case vital14bit
}

struct DeviceProfile: Identifiable, Hashable {
  let id: String
  let label: String
  let parent: CBUUID
  let rx: [CBUUID]
  let tx: [CBUUID]
  let unlock: CBUUID
  let unlockMode: UnlockMode
  let userStart: [Int]
  let recordCount: [Int]
  let recordSize: Int
  let blockSize: Int
  let parser: RecordParserKind
  let settingsRead: Int
  let settingsWrite: Int
  let timeSync: (Int, Int)
  let timeLayout: TimeLayout

  static func == (lhs: DeviceProfile, rhs: DeviceProfile) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }

  static let all: [DeviceProfile] = [u705t, hem7142t2, hem7146t, hem7600t]

  static let u705t = DeviceProfile(
    id: "U705T",
    label: "U705T / HEM-7142T2 (modern)",
    parent: OmronUUIDs.fe4a,
    rx: [OmronUUIDs.rx0],
    tx: [OmronUUIDs.tx0],
    unlock: OmronUUIDs.unlock,
    unlockMode: .token,
    userStart: [0x02E8],
    recordCount: [14],
    recordSize: 0x0E,
    blockSize: 0x2C,
    parser: .vital14,
    settingsRead: 0x0260,
    settingsWrite: 0x02A4,
    timeSync: (0x2C, 0x3C),
    timeLayout: .modernOffset8
  )

  static let hem7142t2 = DeviceProfile(
    id: "HEM-7142T2",
    label: "HEM-7142T2",
    parent: OmronUUIDs.fe4a,
    rx: [OmronUUIDs.rx0],
    tx: [OmronUUIDs.tx0],
    unlock: OmronUUIDs.unlock,
    unlockMode: .token,
    userStart: [0x02E8],
    recordCount: [14],
    recordSize: 0x0E,
    blockSize: 0x2C,
    parser: .vital14,
    settingsRead: 0x0260,
    settingsWrite: 0x02A4,
    timeSync: (0x2C, 0x3C),
    timeLayout: .modernOffset8
  )

  static let hem7146t = DeviceProfile(
    id: "HEM-7146T",
    label: "HEM-7146T / X2 Smart+",
    parent: OmronUUIDs.fe4a,
    rx: [OmronUUIDs.rx0],
    tx: [OmronUUIDs.tx0],
    unlock: OmronUUIDs.unlock,
    unlockMode: .token,
    userStart: [0x02E8],
    recordCount: [30],
    recordSize: 0x0E,
    blockSize: 0x2C,
    parser: .vital14,
    settingsRead: 0x0260,
    settingsWrite: 0x02A4,
    timeSync: (0x2C, 0x3C),
    timeLayout: .modernOffset8
  )

  static let hem7600t = DeviceProfile(
    id: "HEM-7600T",
    label: "HEM-7600T / EVOLV (classic key)",
    parent: OmronUUIDs.classic,
    rx: OmronUUIDs.classicRX,
    tx: OmronUUIDs.classicTX,
    unlock: OmronUUIDs.unlock,
    unlockMode: .classic,
    userStart: [0x02AC],
    recordCount: [100],
    recordSize: 0x0E,
    blockSize: 0x2C,
    parser: .vital14bit,
    settingsRead: 0x0260,
    settingsWrite: 0x0286,
    timeSync: (0x14, 0x1E),
    timeLayout: .classicMixed
  )
}
