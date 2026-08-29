import CoreBluetooth

enum OmronUUIDs {
  static let fe4a = CBUUID(string: "0000FE4A-0000-1000-8000-00805F9B34FB")
  static let classic = CBUUID(string: "ECBE3980-C9A2-11E1-B1BD-0002A5D5C51B")
  static let dis = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB")
  static let cts = CBUUID(string: "00001805-0000-1000-8000-00805F9B34FB")
  static let charCTS = CBUUID(string: "00002A2B-0000-1000-8000-00805F9B34FB")
  static let charLTI = CBUUID(string: "00002A0F-0000-1000-8000-00805F9B34FB")
  static let unlock = CBUUID(string: "B305B680-AEE7-11E1-A730-0002A5D5C51B")
  static let rx0 = CBUUID(string: "49123040-AEE8-11E1-A74D-0002A5D5C51B")
  static let tx0 = CBUUID(string: "DB5B55E0-AEE7-11E1-965E-0002A5D5C51B")

  static let classicRX: [CBUUID] = [
    rx0,
    CBUUID(string: "4D0BF320-AEE8-11E1-A0D9-0002A5D5C51B"),
    CBUUID(string: "5128CE60-AEE8-11E1-B84B-0002A5D5C51B"),
    CBUUID(string: "560F1420-AEE8-11E1-8184-0002A5D5C51B"),
  ]

  static let classicTX: [CBUUID] = [
    tx0,
    CBUUID(string: "E0B8A060-AEE7-11E1-92F4-0002A5D5C51B"),
    CBUUID(string: "0AE12B00-AEE8-11E1-A192-0002A5D5C51B"),
    CBUUID(string: "10E1BA60-AEE8-11E1-89E5-0002A5D5C51B"),
  ]

  static let pairingKey = Data([
    0xDE, 0xAD, 0xBE, 0xAF, 0x12, 0x34, 0x12, 0x34,
    0xDE, 0xAD, 0xBE, 0xAF, 0x12, 0x34, 0x12, 0x34,
  ])

  static let scanServices: [CBUUID] = [fe4a, classic]
}
