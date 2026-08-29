import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  @Published var profile: DeviceProfile = .u705t
  @Published var readings: [BPReading] = []
  @Published var logText = "Ready. Unpair the Omron app, then hold Bluetooth on the cuff until -P- blinks."
  @Published var status = ""
  @Published var statusOK = false
  @Published var busy = false
  @Published var scanning = false
  @Published var healthReady = false
  @Published var healthMessage = "Apple Health not connected yet."

  let ble = OmronBleClient()
  let health = HealthStoreClient()

  var latest: BPReading? { readings.first }
  var goodCount: Int { readings.filter { $0.category.rating == "Good" }.count }
  var badCount: Int { readings.count - goodCount }

  func boot() async {
    do {
      try await ble.waitUntilPoweredOn()
    } catch {
      status = error.localizedDescription
      statusOK = false
    }
    await connectHealth(prompt: false)
  }

  func connectHealth(prompt: Bool) async {
    guard health.isAvailable else {
      healthMessage = "Apple Health is not available on this device."
      return
    }
    do {
      if prompt {
        try await health.requestAccess()
      } else {
        try await health.requestAccess()
      }
      healthReady = true
      healthMessage = "Apple Health is authorized. New downloads can be saved."
    } catch {
      healthReady = false
      healthMessage = error.localizedDescription
    }
  }

  func startScan() {
    scanning = true
    status = "Scanning for Omron cuffs…"
    statusOK = false
    ble.startScan()
  }

  func stopScan() {
    ble.stopScan()
    scanning = false
  }

  func connect(_ cuff: DiscoveredCuff) async {
    busy = true
    stopScan()
    status = "Connecting…"
    statusOK = false
    do {
      try await ble.connect(to: cuff, profile: profile, log: { [weak self] line in
        Task { @MainActor in
          self?.appendLog(line)
        }
      })
      status = "Downloading stored readings…"
      readings = try await ble.pullReadings()
      persist()
      status = "Downloaded \(readings.count) reading(s)."
      statusOK = true
      if healthReady {
        await saveToHealth()
      }
    } catch {
      appendLog(error.localizedDescription)
      status = error.localizedDescription
      statusOK = false
    }
    busy = false
  }

  func disconnect() async {
    await ble.disconnect()
    status = "Disconnected."
    statusOK = false
  }

  func syncClock() async {
    busy = true
    status = "Writing phone time to the cuff…"
    do {
      let result = try await ble.syncTime()
      var parts: [String] = []
      if result.eeprom { parts.append("EEPROM") }
      if result.cts { parts.append("CTS") }
      status = "Clock updated (\(parts.joined(separator: " + ")))."
      statusOK = true
    } catch {
      appendLog(error.localizedDescription)
      status = error.localizedDescription
      statusOK = false
    }
    busy = false
  }

  func saveToHealth() async {
    do {
      try await health.requestAccess()
      healthReady = true
      let result = try await health.save(readings)
      healthMessage = "Saved \(result.saved) to Apple Health (\(result.skipped) already there)."
      status = healthMessage
      statusOK = true
    } catch {
      healthReady = false
      healthMessage = error.localizedDescription
      status = error.localizedDescription
      statusOK = false
    }
  }

  func csv() -> String {
    let header = "time,user,systolic,diastolic,pulse,rating,category,movement,irregular,cuff,battery"
    let lines = readings.map { r in
      [
        r.datetime?.ISO8601Format() ?? "",
        String(r.user),
        String(r.sys),
        String(r.dia),
        String(r.bpm),
        r.category.rating,
        r.category.label,
        String(r.mov),
        String(r.ihb),
        String(r.cuff),
        String(r.battery),
      ].joined(separator: ",")
    }
    return ([header] + lines).joined(separator: "\n")
  }

  func json() -> String {
    struct ExportRow: Encodable {
      let time: String?
      let user: Int
      let systolic: Int
      let diastolic: Int
      let pulse: Int
      let rating: String
      let category: String
      let movement: Int
      let irregular: Int
      let cuff: Int
      let battery: Int
    }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let rows = readings.map {
      ExportRow(
        time: $0.datetime?.ISO8601Format(),
        user: $0.user,
        systolic: $0.sys,
        diastolic: $0.dia,
        pulse: $0.bpm,
        rating: $0.category.rating,
        category: $0.category.label,
        movement: $0.mov,
        irregular: $0.ihb,
        cuff: $0.cuff,
        battery: $0.battery
      )
    }
    return (try? String(data: enc.encode(rows), encoding: .utf8)) ?? "[]"
  }

  func appendLog(_ line: String) {
    let stamp = Date.now.formatted(date: .omitted, time: .standard)
    logText += "\n\(stamp) \(line)"
  }

  private func persist() {
    let url = Self.storeURL
    if let data = try? JSONEncoder().encode(readings) {
      try? data.write(to: url)
    }
  }

  func loadPersisted() {
    let url = Self.storeURL
    if let data = try? Data(contentsOf: url),
       let rows = try? JSONDecoder().decode([BPReading].self, from: data) {
      readings = rows
    }
  }

  private static var storeURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("readings.json")
  }
}
