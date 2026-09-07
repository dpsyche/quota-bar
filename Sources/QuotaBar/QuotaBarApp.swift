import SwiftUI

@main
@MainActor
struct QuotaBarApp: App {
  @StateObject private var model: AppModel

  init() {
    #if QUOTABAR_NATIVE_TEST
      let model = NativeLabelProbe.makeModel()
    #else
      let model = AppModel()
    #endif
    _model = StateObject(wrappedValue: model)
    model.start()
    #if QUOTABAR_NATIVE_TEST
      NativeLabelProbe.start(model: model)
    #endif
  }

  var body: some Scene {
    MenuBarExtra {
      QuotaPopoverView()
        .environmentObject(model)
        .preferredColorScheme(.dark)
        #if QUOTABAR_NATIVE_TEST
          .onAppear { NativeLabelProbe.popoverAppeared = true }
        #endif
    } label: {
      StatusRingView(signal: model.headlineSignal)
        .accessibilityLabel(model.headlineAccessibilityLabel)
        .help(model.headlineAccessibilityLabel)
    }
    .menuBarExtraStyle(.window)
  }
}
