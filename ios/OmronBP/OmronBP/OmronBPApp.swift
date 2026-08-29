import SwiftUI

@main
struct OmronBPApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .tint(Theme.dia)
    }
  }
}
