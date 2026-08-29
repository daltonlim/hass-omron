import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @State private var shareCSV = false
  @State private var shareJSON = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          header
          devicePanel
          healthPanel
          stats
          TimeSeriesChartView(readings: model.readings)
          RangeGuideChartView(readings: model.readings)
          readingsList
          logPanel
        }
        .padding()
      }
      .background(Theme.paper.ignoresSafeArea())
      .navigationTitle("Omron reader")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Export CSV") { shareCSV = true }
            Button("Export JSON") { shareJSON = true }
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
        }
      }
      .sheet(isPresented: $shareCSV) { ShareSheet(text: model.csv(), filename: "omron-readings.csv") }
      .sheet(isPresented: $shareJSON) { ShareSheet(text: model.json(), filename: "omron-readings.json") }
      .task {
        model.loadPersisted()
        await model.boot()
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("hass-omron")
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.dia)
        .textCase(.uppercase)
      Text("Read the cuff over Bluetooth")
        .font(.title.weight(.semibold))
        .foregroundStyle(Theme.ink)
      Text("The cuff can only stay paired with one host. Unpair it from the Omron app first, then hold Bluetooth until -P- blinks. ACC/AHA colours are guidelines, not a diagnosis.")
        .font(.subheadline)
        .foregroundStyle(Theme.muted)
    }
  }

  private var devicePanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Device").font(.headline)
      Picker("Profile", selection: $model.profile) {
        ForEach(DeviceProfile.all) { profile in
          Text(profile.label).tag(profile)
        }
      }
      .pickerStyle(.menu)

      if !model.status.isEmpty {
        Text(model.status)
          .font(.caption)
          .foregroundStyle(model.statusOK ? Theme.dia : Theme.sys)
      }

      HStack {
        Button(model.scanning ? "Stop scan" : "Scan") {
          model.scanning ? model.stopScan() : model.startScan()
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.busy)

        Button("Disconnect") {
          Task { await model.disconnect() }
        }
        .buttonStyle(.bordered)
        .disabled(model.busy || !model.ble.isConnected)

        Button("Set cuff clock") {
          Task { await model.syncClock() }
        }
        .buttonStyle(.bordered)
        .disabled(model.busy || !model.ble.isConnected)
      }

      if model.busy {
        ProgressView()
      }

      ForEach(model.ble.discovered) { cuff in
        Button {
          Task { await model.connect(cuff) }
        } label: {
          HStack {
            VStack(alignment: .leading) {
              Text(cuff.name).foregroundStyle(Theme.ink)
              Text("RSSI \(cuff.rssi)").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("Connect").font(.caption.weight(.semibold))
          }
          .padding(10)
          .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(model.busy)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
  }

  private var healthPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Apple Health").font(.headline)
      Text(model.healthMessage)
        .font(.subheadline)
        .foregroundStyle(Theme.muted)
      HStack {
        Button("Allow Health access") {
          Task { await model.connectHealth(prompt: true) }
        }
        .buttonStyle(.borderedProminent)
        Button("Save readings") {
          Task { await model.saveToHealth() }
        }
        .buttonStyle(.bordered)
        .disabled(model.readings.isEmpty)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
  }

  private var stats: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
      StatCard(title: "Latest systolic", value: model.latest.map { "\($0.sys)" })
      StatCard(title: "Latest diastolic", value: model.latest.map { "\($0.dia)" })
      StatCard(title: "Latest pulse", value: model.latest.map { "\($0.bpm)" })
      StatCard(title: "Readings", value: "\(model.readings.count)")
      StatCard(
        title: "Latest rating",
        accessory: model.latest.map { AnyView(Lozenge(category: $0.category, large: true)) }
      )
      StatCard(
        title: "Good / bad",
        value: model.readings.isEmpty ? "—" : "\(model.goodCount) / \(model.badCount)"
      )
    }
  }

  private var readingsList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("History").font(.headline)
      if model.readings.isEmpty {
        Text("Connect a cuff to pull stored measurements.")
          .foregroundStyle(Theme.muted)
      } else {
        ForEach(model.readings) { row in
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              Text(row.datetime?.formatted() ?? "—")
                .font(.subheadline.weight(.semibold))
              Text("\(row.sys)/\(row.dia) · pulse \(row.bpm)")
              Text(row.flags).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Lozenge(category: row.category)
          }
          .padding(.vertical, 6)
          Divider()
        }
      }
    }
    .padding(14)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
  }

  private var logPanel: some View {
    Text(model.logText)
      .font(.footnote.monospaced())
      .foregroundStyle(Theme.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

struct ShareSheet: UIViewControllerRepresentable {
  let text: String
  let filename: String

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try? text.data(using: .utf8)?.write(to: url)
    return UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
