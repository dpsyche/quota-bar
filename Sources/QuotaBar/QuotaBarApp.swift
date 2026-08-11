import SwiftUI

@main
@MainActor
struct QuotaBarApp: App {
  @StateObject private var model: AppModel

  init() {
    let model = AppModel()
    _model = StateObject(wrappedValue: model)
    model.start()
  }

  var body: some Scene {
    MenuBarExtra {
      QuotaPopoverView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
    } label: {
      StatusRingView(signal: model.headlineSignal)
        .accessibilityLabel(model.headlineAccessibilityLabel)
        .help(model.headlineAccessibilityLabel)
    }
    .menuBarExtraStyle(.window)
  }
}
