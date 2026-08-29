import CryptoKit
import Foundation
import HealthKit

struct HealthSyncResult {
  var saved: Int
  var skipped: Int
}

final class HealthStoreClient {
  private let store = HKHealthStore()
  private let syncedKey = "healthSyncedIds"

  var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  private var systolicType: HKQuantityType { HKQuantityType(.bloodPressureSystolic) }
  private var diastolicType: HKQuantityType { HKQuantityType(.bloodPressureDiastolic) }
  private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
  private var correlationType: HKCorrelationType { HKCorrelationType(.bloodPressure) }

  func requestAccess() async throws {
    guard isAvailable else { return }
    try await store.requestAuthorization(
      toShare: [systolicType, diastolicType, heartRateType],
      read: [systolicType, diastolicType, heartRateType]
    )
  }

  func save(_ readings: [BPReading]) async throws -> HealthSyncResult {
    guard isAvailable else { return HealthSyncResult(saved: 0, skipped: readings.count) }
    var synced = Set(UserDefaults.standard.stringArray(forKey: syncedKey) ?? [])
    var saved = 0
    var skipped = 0
    var objects: [HKSample] = []
    for reading in readings {
      guard let date = reading.datetime else {
        skipped += 1
        continue
      }
      let ext = Self.externalUUID(for: reading)
      if synced.contains(ext) {
        skipped += 1
        continue
      }
      let meta: [String: Any] = [
        HKMetadataKeyExternalUUID: ext,
        HKMetadataKeyWasUserEntered: false,
      ]
      let sys = HKQuantitySample(
        type: systolicType,
        quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double(reading.sys)),
        start: date,
        end: date,
        metadata: meta
      )
      let dia = HKQuantitySample(
        type: diastolicType,
        quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double(reading.dia)),
        start: date,
        end: date,
        metadata: meta
      )
      let bp = HKCorrelation(
        type: correlationType,
        start: date,
        end: date,
        objects: [sys, dia],
        metadata: meta
      )
      let hr = HKQuantitySample(
        type: heartRateType,
        quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(reading.bpm)),
        start: date,
        end: date,
        metadata: meta
      )
      objects.append(bp)
      objects.append(hr)
      synced.insert(ext)
      saved += 1
    }
    if !objects.isEmpty {
      try await store.save(objects)
    }
    UserDefaults.standard.set(Array(synced), forKey: syncedKey)
    return HealthSyncResult(saved: saved, skipped: skipped)
  }

  static func externalUUID(for reading: BPReading) -> String {
    let digest = SHA256.hash(data: Data(reading.id.utf8))
    let bytes = Array(digest.prefix(16))
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let parts = [
      String(hex.prefix(8)),
      String(hex.dropFirst(8).prefix(4)),
      String(hex.dropFirst(12).prefix(4)),
      String(hex.dropFirst(16).prefix(4)),
      String(hex.dropFirst(20).prefix(12)),
    ]
    return parts.joined(separator: "-")
  }
}
