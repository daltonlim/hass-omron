import CoreBluetooth
import Foundation
import Security

struct DiscoveredCuff: Identifiable, Hashable {
  var id: UUID { peripheral.identifier }
  let peripheral: CBPeripheral
  let name: String
  let rssi: Int

  static func == (lhs: DiscoveredCuff, rhs: DiscoveredCuff) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

final class ResumeBox<T> {
  private var continuation: CheckedContinuation<T, Error>?
  private let lock = NSLock()

  func arm(_ continuation: CheckedContinuation<T, Error>) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()
  }

  func resume(returning value: T) {
    lock.lock()
    let cont = continuation
    continuation = nil
    lock.unlock()
    cont?.resume(returning: value)
  }

  func resume(throwing error: Error) {
    lock.lock()
    let cont = continuation
    continuation = nil
    lock.unlock()
    cont?.resume(throwing: error)
  }

  var isArmed: Bool {
    lock.lock()
    defer { lock.unlock() }
    return continuation != nil
  }
}

@MainActor
final class OmronBleClient: NSObject, ObservableObject {
  @Published var discovered: [DiscoveredCuff] = []
  @Published var bluetoothState: CBManagerState = .unknown

  private var central: CBCentralManager!
  private var peripheral: CBPeripheral?
  private var profile: DeviceProfile = .u705t
  private var rxChars: [CBCharacteristic] = []
  private var txChars: [CBCharacteristic] = []
  private var unlockChar: CBCharacteristic?
  private var ctsChar: CBCharacteristic?
  private var ltiChar: CBCharacteristic?
  private var fragments: [Data?] = [nil, nil, nil, nil]
  private var memoryOpen = false
  private var logHandler: (String) -> Void = { _ in }

  private let ready = ResumeBox<Void>()
  private let connected = ResumeBox<Void>()
  private let servicesReady = ResumeBox<Void>()
  private let notifyReady = ResumeBox<Void>()
  private let writeReady = ResumeBox<Void>()
  private let unlockAck = ResumeBox<Data>()
  private let replyBox = ResumeBox<MemoryReply>()
  private var expectedType = ""
  private var waitingNotifyUUID: CBUUID?

  var isConnected: Bool { peripheral?.state == .connected }

  override init() {
    super.init()
    central = CBCentralManager(delegate: self, queue: .main)
  }

  func log(_ line: String) {
    logHandler(line)
  }

  func waitUntilPoweredOn() async throws {
    if bluetoothState == .poweredOn { return }
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      ready.arm(cont)
    }
  }

  func startScan() {
    discovered = []
    guard bluetoothState == .poweredOn else { return }
    central.scanForPeripherals(
      withServices: OmronUUIDs.scanServices,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    // Also pick up already-connected Omron cuffs (iOS may already hold the GATT link).
    for item in central.retrieveConnectedPeripherals(withServices: OmronUUIDs.scanServices) {
      upsert(item, rssi: 0)
    }
  }

  func stopScan() {
    central.stopScan()
  }

  func connect(to cuff: DiscoveredCuff, profile: DeviceProfile, log: @escaping (String) -> Void) async throws {
    self.profile = profile
    self.logHandler = log
    stopScan()
    log("Connecting to \(cuff.name)…")
    peripheral = cuff.peripheral
    cuff.peripheral.delegate = self
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      connected.arm(cont)
      central.connect(cuff.peripheral, options: nil)
    }
    try await sleep(1200)
    log("Discovering services…")
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      servicesReady.arm(cont)
      cuff.peripheral.discoverServices([profile.parent, OmronUUIDs.dis, OmronUUIDs.cts])
    }
    log("GATT ready. Unlocking…")
    try await unlock()
    log("Opening memory session…")
    try await subscribeRx()
    try await sleep(750)
    let start = ProtocolCodec.hexToData("0800000000100018")
    let reply = try await command(start, expect: "8000")
    if let code = reply.payload.first, code != 0 {
      throw ProtocolError.deviceRejected(code)
    }
    memoryOpen = true
  }

  func disconnect() async {
    if let peripheral, peripheral.state == .connected {
      do {
        _ = try await command(ProtocolCodec.hexToData("080f000000000007"), expect: "8f00")
      } catch {
        log("Close ignored: \(error.localizedDescription)")
      }
      central.cancelPeripheralConnection(peripheral)
    }
    memoryOpen = false
    rxChars = []
    txChars = []
    unlockChar = nil
    self.peripheral = nil
  }

  func pullReadings() async throws -> [BPReading] {
    var readings: [BPReading] = []
    for user in 0..<profile.userStart.count {
      let base = profile.userStart[user]
      let count = profile.recordCount[user]
      let size = profile.recordSize
      log(String(format: "Reading user %d: 0x%04x × %d", user + 1, base, count))
      let raw = try await readRange(start: base, length: count * size)
      for slot in 0..<count {
        let rec = raw.subdata(in: (slot * size)..<((slot + 1) * size))
        if rec.allSatisfy({ $0 == 0xFF }) { continue }
        do {
          var parsed: BPReading
          switch profile.parser {
          case .vital14: parsed = try ProtocolCodec.parseVital14(rec)
          case .vital14bit: parsed = try ProtocolCodec.parseVital14Bit(rec)
          }
          parsed.user = user + 1
          parsed.slot = slot
          readings.append(parsed)
        } catch {
          continue
        }
      }
    }
    readings.sort { ($0.datetime ?? .distantPast) > ($1.datetime ?? .distantPast) }
    return readings
  }

  func syncTime() async throws -> (eeprom: Bool, cts: Bool) {
    var eeprom = false
    try await openMemory()
    eeprom = try await syncEepromTime()
    do {
      try await closeMemory()
    } catch {
      log("Memory close before CTS: \(error.localizedDescription)")
    }
    let cts = await syncCtsTime()
    do {
      try await openMemory()
    } catch {
      log("Could not reopen memory session: \(error.localizedDescription)")
    }
    if !eeprom && !cts { throw ProtocolError.timeSyncFailed }
    return (eeprom, cts)
  }

  private func unlock() async throws {
    if profile.unlockMode == .token {
      try await tokenUnlock()
    } else {
      try await classicUnlock()
    }
  }

  private func tokenUnlock() async throws {
    var token = Data(count: 4)
    token.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
    var packet = Data(count: 20)
    packet[0] = 0x11
    packet.replaceSubrange(1..<5, with: token)
    guard let unlockChar, let rx0 = rxChars.first else {
      throw ProtocolError.missingCharacteristic("unlock")
    }
    try await setNotify(true, for: unlockChar)
    try? await setNotify(true, for: rx0)
    try await sleep(750)
    do {
      try await tokenWrite(packet, token: token, withResponse: false)
    } catch {
      log("Token write-without-response timed out; retrying with response")
      try await tokenWrite(packet, token: token, withResponse: true)
    }
    try? await setNotify(false, for: unlockChar)
    log("Token unlock OK (\(ProtocolCodec.hex(token)))")
  }

  private func tokenWrite(_ packet: Data, token: Data, withResponse: Bool) async throws {
    let ack = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
      self.unlockAck.arm(cont)
      Task { @MainActor in
        try? await self.sleep(5000)
        self.unlockAck.resume(throwing: ProtocolError.timeout)
      }
      self.write(packet, for: self.unlockChar!, withResponse: withResponse)
    }
    guard ack.count >= 6, ack[0] == 0x91, ack[1] == 0x00, ack.subdata(in: 2..<6) == token else {
      throw ProtocolError.timeout
    }
  }

  private func classicUnlock() async throws {
    guard let unlockChar else { throw ProtocolError.missingCharacteristic("unlock") }
    var packet = Data([0x01])
    packet.append(OmronUUIDs.pairingKey)
    try await setNotify(true, for: unlockChar)
    try await sleep(750)
    let ack = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
      self.unlockAck.arm(cont)
      Task { @MainActor in
        try? await self.sleep(5000)
        self.unlockAck.resume(throwing: ProtocolError.timeout)
      }
      self.write(packet, for: unlockChar, withResponse: true)
    }
    try? await setNotify(false, for: unlockChar)
    guard ack.first == 0x81 else { throw ProtocolError.timeout }
    log("Classic pairing-key unlock OK")
  }

  private func subscribeRx() async throws {
    for ch in rxChars {
      try? await setNotify(true, for: ch)
    }
  }

  private func command(_ body: Data, expect expectType: String?) async throws -> MemoryReply {
    let cmd: Data
    if ProtocolCodec.xorCrc(body) == 0 && body.count >= 8 {
      cmd = body
    } else {
      cmd = ProtocolCodec.withXor(body.dropLast())
    }
    let expect = expectType ?? String(format: "%02x%02x", cmd[1] | 0x80, cmd[2])
    var lastError: Error = ProtocolError.noReply
    for attempt in 0..<4 {
      do {
        expectedType = expect
        let width = profile.tx.count == 1 ? max(16, cmd.count) : 16
        let got = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MemoryReply, Error>) in
          self.replyBox.arm(cont)
          Task { @MainActor in
            try? await self.sleep(5000)
            self.replyBox.resume(throwing: ProtocolError.timeout)
          }
          var offset = 0
          var channel = 0
          while offset < cmd.count {
            let end = min(offset + width, cmd.count)
            let slice = cmd.subdata(in: offset..<end)
            self.write(slice, for: self.txChars[channel], withResponse: self.profile.tx.count != 1)
            offset = end
            channel += 1
          }
        }
        if got.type == "8f00" && expect != "8f00" {
          throw ProtocolError.deviceRejected(got.payload.first ?? 0)
        }
        return got
      } catch {
        lastError = error
        log("TX retry \(attempt + 1)/4: \(error.localizedDescription)")
        try await sleep(250)
      }
    }
    throw lastError
  }

  private func readBlock(address: Int, size: Int) async throws -> Data {
    var cmd = Data(count: 7)
    cmd[0] = 0x08
    cmd[1] = 0x01
    cmd[2] = 0x00
    cmd[3] = UInt8((address >> 8) & 0xFF)
    cmd[4] = UInt8(address & 0xFF)
    cmd[5] = UInt8(size & 0xFF)
    let reply = try await command(ProtocolCodec.withXor(cmd), expect: "8100")
    let gotAddr = Int(reply.addr, radix: 16) ?? -1
    if gotAddr != address {
      throw ProtocolError.addressMismatch(reply.addr)
    }
    return reply.payload
  }

  private func readRange(start: Int, length: Int) async throws -> Data {
    var out = Data()
    var addr = start
    var left = length
    while left > 0 {
      let chunk = min(left, profile.blockSize)
      out.append(try await readBlock(address: addr, size: chunk))
      addr += chunk
      left -= chunk
    }
    return out
  }

  private func writeBlock(address: Int, data: Data) async throws {
    var prefix = Data([UInt8(data.count + 8), 0x01, 0xC0, UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF), UInt8(data.count)])
    prefix.append(data)
    prefix.append(0x00)
    let reply = try await command(ProtocolCodec.withXor(prefix), expect: "81c0")
    let gotAddr = Int(reply.addr, radix: 16) ?? -1
    if gotAddr != address {
      throw ProtocolError.addressMismatch(reply.addr)
    }
  }

  private func closeMemory() async throws {
    guard memoryOpen else { return }
    _ = try await command(ProtocolCodec.hexToData("080f000000000007"), expect: "8f00")
    memoryOpen = false
  }

  private func openMemory() async throws {
    if memoryOpen { return }
    let reply = try await command(ProtocolCodec.hexToData("0800000000100018"), expect: "8000")
    if let code = reply.payload.first, code != 0 {
      throw ProtocolError.deviceRejected(code)
    }
    memoryOpen = true
  }

  private func syncEepromTime() async throws -> Bool {
    let (sectionStart, sectionEnd) = profile.timeSync
    let size = sectionEnd - sectionStart
    let cached = try await readRange(start: profile.settingsRead + sectionStart, length: size)
    let deviceDt = ProtocolCodec.decodeEepromTime(cached, layout: profile.timeLayout)
    let now = Date()
    if let deviceDt {
      let diff = abs(now.timeIntervalSince(deviceDt))
      log("Cuff clock \(deviceDt.formatted()) (delta \(Int(diff))s)")
      if diff <= 60 {
        log("Clock already within 60s; skipping EEPROM write")
        return true
      }
    } else {
      log("Cuff clock unreadable; writing phone time")
    }
    let payload = ProtocolCodec.encodeEepromTime(cached, now: now, layout: profile.timeLayout)
    try await writeBlock(address: profile.settingsWrite + sectionStart, data: payload)
    try await sleep(1000)
    log("Wrote cuff clock \(now.formatted())")
    return true
  }

  private func syncCtsTime() async -> Bool {
    guard let ctsChar else {
      log("CTS not available")
      return false
    }
    let now = Date()
    do {
      try await writeAwait(ProtocolCodec.ctsPayload(now: now), for: ctsChar, withResponse: true)
      log("Wrote Current Time Service")
      if let ltiChar {
        try? await writeAwait(ProtocolCodec.localTimeInfo(now: now), for: ltiChar, withResponse: true)
      }
      return true
    } catch {
      log("CTS not available (\(error.localizedDescription))")
      return false
    }
  }

  private func onUnlockNotify(_ data: Data) {
    unlockAck.resume(returning: data)
  }

  private func onRx(characteristic: CBCharacteristic, bytes: Data) {
    let idx = rxChars.firstIndex(where: { $0.uuid == characteristic.uuid }) ?? 0
    if idx == 0 { fragments = [nil, nil, nil, nil] }
    fragments[idx] = bytes
    guard let first = fragments[0] else { return }
    let frame: Data
    let single = profile.tx.count == 1
    if single {
      var candidate = first
      fragments = [nil, nil, nil, nil]
      let declared = Int(candidate.first ?? 0)
      if declared != 0 && candidate.count < declared { return }
      if declared != 0 { candidate = candidate.prefix(declared) }
      frame = candidate
    } else {
      let packetSize = Int(first.first ?? 0)
      if packetSize == 0 || packetSize > 64 {
        fragments = [nil, nil, nil, nil]
        return
      }
      let needed = Int(ceil(Double(packetSize) / 16.0))
      for i in 0..<needed where fragments[i] == nil { return }
      var combined = Data()
      for i in 0..<needed { combined.append(fragments[i]!) }
      frame = combined.prefix(packetSize)
      fragments = [nil, nil, nil, nil]
    }
    if ProtocolCodec.xorCrc(frame) != 0 {
      log("CRC error: \(ProtocolCodec.hex(frame))")
      return
    }
    guard frame.count >= 8 else { return }
    let type = ProtocolCodec.hex(frame.subdata(in: 1..<3))
    let addr = ProtocolCodec.hex(frame.subdata(in: 3..<5))
    let dataLen = Int(frame[5])
    let payload: Data
    if type == "8100" {
      let end = min(6 + dataLen, frame.count)
      payload = frame.subdata(in: 6..<end)
    } else {
      payload = frame.subdata(in: 6..<min(7, frame.count))
    }
    if replyBox.isArmed && (type == expectedType || type == "8f00") {
      replyBox.resume(returning: MemoryReply(type: type, addr: addr, payload: payload))
    }
  }

  private func upsert(_ peripheral: CBPeripheral, rssi: Int, name: String? = nil) {
    let item = DiscoveredCuff(peripheral: peripheral, name: name ?? peripheral.name ?? "Omron", rssi: rssi)
    if let idx = discovered.firstIndex(where: { $0.id == item.id }) {
      discovered[idx] = item
    } else {
      discovered.append(item)
    }
  }

  private func write(_ data: Data, for characteristic: CBCharacteristic, withResponse: Bool) {
    guard let peripheral else { return }
    let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
    let canWithout = characteristic.properties.contains(.writeWithoutResponse)
    let canWith = characteristic.properties.contains(.write)
    if type == .withoutResponse, canWithout {
      peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    } else if canWith {
      peripheral.writeValue(data, for: characteristic, type: .withResponse)
    } else if canWithout {
      peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
  }

  private func writeAwait(_ data: Data, for characteristic: CBCharacteristic, withResponse: Bool) async throws {
    if withResponse && characteristic.properties.contains(.write) {
      try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        self.writeReady.arm(cont)
        Task { @MainActor in
          try? await self.sleep(5000)
          self.writeReady.resume(throwing: ProtocolError.timeout)
        }
        self.write(data, for: characteristic, withResponse: true)
      }
    } else {
      write(data, for: characteristic, withResponse: false)
    }
  }

  private func setNotify(_ enabled: Bool, for characteristic: CBCharacteristic) async throws {
    guard let peripheral else { throw ProtocolError.disconnected }
    waitingNotifyUUID = characteristic.uuid
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      self.notifyReady.arm(cont)
      Task { @MainActor in
        try? await self.sleep(5000)
        self.notifyReady.resume(throwing: ProtocolError.timeout)
      }
      peripheral.setNotifyValue(enabled, for: characteristic)
    }
    waitingNotifyUUID = nil
  }

  private func sleep(_ ms: UInt64) async throws {
    try await Task.sleep(nanoseconds: ms * 1_000_000)
  }
}

extension OmronBleClient: CBCentralManagerDelegate {
  nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
    Task { @MainActor in
      bluetoothState = central.state
      if central.state == .poweredOn {
        ready.resume(returning: ())
      } else if central.state == .poweredOff || central.state == .unauthorized {
        ready.resume(throwing: ProtocolError.bluetoothUnavailable)
      }
    }
  }

  nonisolated func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    Task { @MainActor in
      let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
      upsert(peripheral, rssi: RSSI.intValue, name: peripheral.name ?? advertised ?? "Omron")
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    Task { @MainActor in
      log("Connected")
      connected.resume(returning: ())
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    Task { @MainActor in
      connected.resume(throwing: error ?? ProtocolError.disconnected)
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    Task { @MainActor in
      memoryOpen = false
      log("Disconnected")
    }
  }
}

extension OmronBleClient: CBPeripheralDelegate {
  nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    Task { @MainActor in
      if let error {
        servicesReady.resume(throwing: error)
        return
      }
      guard let services = peripheral.services else {
        servicesReady.resume(throwing: ProtocolError.missingCharacteristic("service"))
        return
      }
      for service in services {
        peripheral.discoverCharacteristics(nil, for: service)
      }
    }
  }

  nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    Task { @MainActor in
      if let error {
        servicesReady.resume(throwing: error)
        return
      }
      let chars = service.characteristics ?? []
      if service.uuid == profile.parent {
        rxChars = profile.rx.compactMap { uuid in chars.first(where: { $0.uuid == uuid }) }
        txChars = profile.tx.compactMap { uuid in chars.first(where: { $0.uuid == uuid }) }
        unlockChar = chars.first(where: { $0.uuid == profile.unlock })
      }
      if service.uuid == OmronUUIDs.cts {
        ctsChar = chars.first(where: { $0.uuid == OmronUUIDs.charCTS })
        ltiChar = chars.first(where: { $0.uuid == OmronUUIDs.charLTI })
      }
      let pending = (peripheral.services ?? []).contains { $0.characteristics == nil }
      if !pending {
        if unlockChar == nil || rxChars.count != profile.rx.count || txChars.count != profile.tx.count {
          servicesReady.resume(throwing: ProtocolError.missingCharacteristic("Omron GATT"))
        } else {
          servicesReady.resume(returning: ())
        }
      }
    }
  }

  nonisolated func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    Task { @MainActor in
      if waitingNotifyUUID == characteristic.uuid {
        if let error {
          notifyReady.resume(throwing: error)
        } else {
          notifyReady.resume(returning: ())
        }
      }
    }
  }

  nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    Task { @MainActor in
      guard error == nil, let value = characteristic.value else { return }
      if characteristic.uuid == profile.unlock {
        onUnlockNotify(value)
      } else if rxChars.contains(where: { $0.uuid == characteristic.uuid }) {
        onRx(characteristic: characteristic, bytes: value)
      }
    }
  }

  nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    Task { @MainActor in
      if let error {
        writeReady.resume(throwing: error)
      } else {
        writeReady.resume(returning: ())
      }
    }
  }
}
