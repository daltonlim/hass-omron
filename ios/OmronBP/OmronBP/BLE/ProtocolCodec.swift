import Foundation

enum ProtocolError: LocalizedError {
  case emptyRecord
  case shortRecord
  case implausible
  case crc
  case timeout
  case deviceRejected(UInt8)
  case addressMismatch(String)
  case noReply
  case bluetoothUnavailable
  case disconnected
  case missingCharacteristic(String)
  case timeSyncFailed

  var errorDescription: String? {
    switch self {
    case .emptyRecord: return "Empty record"
    case .shortRecord: return "Short record"
    case .implausible: return "Implausible reading"
    case .crc: return "CRC error"
    case .timeout: return "Bluetooth timeout"
    case .deviceRejected(let code): return String(format: "Device rejected session (0x%02x)", code)
    case .addressMismatch(let addr): return "Address mismatch \(addr)"
    case .noReply: return "No memory-protocol reply"
    case .bluetoothUnavailable: return "Bluetooth is not available. Enable it in Settings."
    case .disconnected: return "Disconnected"
    case .missingCharacteristic(let uuid): return "Missing characteristic \(uuid)"
    case .timeSyncFailed: return "Neither EEPROM nor CTS time sync succeeded"
    }
  }
}

enum ProtocolCodec {
  static func xorCrc(_ bytes: Data) -> UInt8 {
    bytes.reduce(UInt8(0)) { $0 ^ $1 }
  }

  static func withXor(_ bytes: Data) -> Data {
    var out = bytes
    out.append(xorCrc(bytes))
    return out
  }

  static func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }

  static func hexToData(_ hex: String) -> Data {
    var clean = hex
    clean.removeAll { !$0.isHexDigit }
    var data = Data()
    var index = clean.startIndex
    while index < clean.endIndex {
      let next = clean.index(index, offsetBy: 2)
      if let byte = UInt8(clean[index..<next], radix: 16) {
        data.append(byte)
      }
      index = next
    }
    return data
  }

  static func bitsToInt(_ data: Data, firstBit: Int, lastBit: Int) -> Int {
    var value = 0
    guard firstBit <= lastBit, lastBit < data.count * 8 else { return 0 }
    for bit in firstBit...lastBit {
      let byte = Int(data[data.startIndex.advanced(by: bit / 8)])
      let bitInByte = 7 - (bit % 8)
      value = (value << 1) | ((byte >> bitInByte) & 1)
    }
    return value
  }

  static func parseVital14(_ data: Data) throws -> BPReading {
    guard data.count >= 8 else { throw ProtocolError.shortRecord }
    let bytes = [UInt8](data)
    let rawSys = Int(bytes[0])
    if rawSys > 0xE1 { throw ProtocolError.emptyRecord }
    let flags1 = Int(bytes[4]) | (Int(bytes[5]) << 8)
    let flags2 = Int(bytes[6]) | (Int(bytes[7]) << 8)
    if bytes[1] == 0 && bytes[2] == 0 && (bytes[3] & 0x3F) == 0 && flags1 == 0 && flags2 == 0 {
      throw ProtocolError.emptyRecord
    }
    let year = 2000 + Int(bytes[3] & 0x3F)
    let hour = flags1 & 0x1F
    let day = (flags1 >> 5) & 0x1F
    let month = (flags1 >> 10) & 0x0F
    let second = min(flags2 & 0x3F, 59)
    let minute = min((flags2 >> 6) & 0x3F, 59)
    let rec = BPReading(
      user: 1,
      slot: 0,
      sys: rawSys + 25,
      dia: Int(bytes[1]),
      bpm: Int(bytes[2]),
      ihb: (flags1 >> 14) & 1,
      mov: (flags1 >> 15) & 1,
      cuff: (flags2 >> 12) & 1,
      battery: (flags2 >> 13) & 1,
      datetime: date(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    )
    try ensurePlausible(rec)
    return rec
  }

  static func parseVital14Bit(_ data: Data) throws -> BPReading {
    let dia = bitsToInt(data, firstBit: 0, lastBit: 7)
    let sys = bitsToInt(data, firstBit: 8, lastBit: 15) + 25
    let year = bitsToInt(data, firstBit: 16, lastBit: 23) + 2000
    let bpm = bitsToInt(data, firstBit: 24, lastBit: 31)
    let month = bitsToInt(data, firstBit: 34, lastBit: 37)
    let day = bitsToInt(data, firstBit: 38, lastBit: 42)
    let hour = bitsToInt(data, firstBit: 43, lastBit: 47)
    let minute = bitsToInt(data, firstBit: 52, lastBit: 57)
    let second = min(bitsToInt(data, firstBit: 58, lastBit: 63), 59)
    let rec = BPReading(
      user: 1,
      slot: 0,
      sys: sys,
      dia: dia,
      bpm: bpm,
      ihb: bitsToInt(data, firstBit: 33, lastBit: 33),
      mov: bitsToInt(data, firstBit: 32, lastBit: 32),
      cuff: bitsToInt(data, firstBit: 51, lastBit: 51),
      battery: bitsToInt(data, firstBit: 50, lastBit: 50),
      datetime: date(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    )
    try ensurePlausible(rec)
    return rec
  }

  static func ensurePlausible(_ rec: BPReading) throws {
    guard rec.sys >= 60, rec.sys <= 260, rec.dia >= 30, rec.dia <= 180, rec.bpm >= 30, rec.bpm <= 220 else {
      throw ProtocolError.implausible
    }
  }

  static func decodeEepromTime(_ cached: Data, layout: TimeLayout) -> Date? {
    let b = [UInt8](cached)
    guard b.count >= 14 else { return nil }
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int
    switch layout {
    case .modernOffset8:
      year = Int(b[8]); month = Int(b[9]); day = Int(b[10])
      hour = Int(b[11]); minute = Int(b[12]); second = Int(b[13])
    case .classicMixed:
      month = Int(b[2]); year = Int(b[3]); hour = Int(b[4])
      day = Int(b[5]); second = Int(b[6]); minute = Int(b[7])
    }
    return date(year: 2000 + year, month: month, day: day, hour: hour, minute: minute, second: min(second, 59))
  }

  static func encodeEepromTime(_ cached: Data, now: Date, layout: TimeLayout) -> Data {
    let cal = Calendar.current
    let y = cal.component(.year, from: now) - 2000
    let month = cal.component(.month, from: now)
    let day = cal.component(.day, from: now)
    let hour = cal.component(.hour, from: now)
    let minute = cal.component(.minute, from: now)
    let second = cal.component(.second, from: now)
    var result: [UInt8]
    switch layout {
    case .modernOffset8:
      result = Array(cached.prefix(8))
      result += [UInt8(y), UInt8(month), UInt8(day), UInt8(hour), UInt8(minute), UInt8(second)]
      result.append(UInt8(result.reduce(0) { Int($0) + Int($1) } & 0xFF))
      result.append(0x00)
    case .classicMixed:
      result = Array(cached.prefix(2))
      result += [UInt8(month), UInt8(y), UInt8(hour), UInt8(day), UInt8(second), UInt8(minute), 0x00]
      result.append(UInt8(result.reduce(0) { Int($0) + Int($1) } & 0xFF))
    }
    return Data(result)
  }

  static func ctsPayload(now: Date) -> Data {
    let cal = Calendar.current
    let year = cal.component(.year, from: now)
    let weekday = cal.component(.weekday, from: now)
    let isoWeekday = weekday == 1 ? 7 : weekday - 1
    return Data([
      UInt8(year & 0xFF),
      UInt8((year >> 8) & 0xFF),
      UInt8(cal.component(.month, from: now)),
      UInt8(cal.component(.day, from: now)),
      UInt8(cal.component(.hour, from: now)),
      UInt8(cal.component(.minute, from: now)),
      UInt8(cal.component(.second, from: now)),
      UInt8(isoWeekday),
      0x00,
      0x00,
    ])
  }

  static func localTimeInfo(now: Date) -> Data {
    let offsetMins = TimeZone.current.secondsFromGMT(for: now) / 60
    let tz15 = UInt8(truncatingIfNeeded: offsetMins / 15)
    return Data([tz15, 0x00])
  }

  private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date? {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = second
    return Calendar.current.date(from: comps)
  }
}

struct MemoryReply {
  let type: String
  let addr: String
  let payload: Data
}
