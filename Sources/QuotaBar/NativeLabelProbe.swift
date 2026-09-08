#if QUOTABAR_NATIVE_TEST
  import AppKit
  import QuotaBarCore

  /// Compiled only by scripts/test-native-label.sh; never present in the release app.
  @MainActor
  enum NativeLabelProbe {
    static var popoverAppeared = false
    private static var directory: URL!
    private static var testDefaults: UserDefaults!
    private static var preferencesName: String!

    static func makeModel() -> AppModel {
      guard (2...3).contains(CommandLine.arguments.count),
        let identifier = Bundle.main.bundleIdentifier,
        identifier.hasPrefix("local.QuotaBar.NativeTest.")
      else { fatalError("Native test requires an isolated bundle and directory") }
      directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      // Foundation rejects a suite equal to this process's bundle identifier.
      preferencesName = identifier + ".volatile-inputs"
      let defaults = UserDefaults(suiteName: preferencesName)!
      testDefaults = defaults
      defaults.setVolatileDomain(
        [AppModel.configuredPathKey: directory.appendingPathComponent("collector").path],
        forName: UserDefaults.argumentDomain)
      return AppModel(
        cache: FileSnapshotCache(fileURL: directory.appendingPathComponent("snapshot.json")),
        defaults: defaults)
    }

    static func start(model: AppModel) {
      if CommandLine.arguments.last == "--manual" { return }
      // Independent watchdog also bounds a wedged main actor; affects only this test process.
      DispatchQueue.global().asyncAfter(deadline: .now() + 15) { exit(1) }
      Task { @MainActor in
        do {
          var initialPixels: Data?
          let deadline = Date().addingTimeInterval(12)
          while Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            guard let button = NSApp.windows.compactMap({ findButton($0.contentView) }).first
            else { continue }
            if initialPixels == nil {
              try require(model.isRefreshing && model.state.report == nil, "missed delayed loading")
              try require(model.headlineSignal == .neutral, "loading is not neutral")
              initialPixels = try pixels(button)
              log("PASS loading: native image, nonempty ring pixels, empty title")
            } else if !model.isRefreshing, model.state.report != nil {
              try require(model.headlineSignal == .caution, "synthetic headline is not caution")
              let refreshed = try pixels(button)
              // Give SwiftUI a bounded opportunity to propagate the model update.
              if refreshed == initialPixels { continue }
              log("PASS refresh: native image pixels changed from neutral to caution")
              try require(button.action != nil && button.isEnabled, "missing native action")
              button.performClick(nil)
              for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 100_000_000)
                if popoverAppeared {
                  log("PASS action: real quota popover appeared")
                  try await presentationEvidence(model: model, button: button)
                  log("PASS native label regression (not physical-screen evidence)")
                  testDefaults.removePersistentDomain(forName: preferencesName)
                  NSApp.terminate(nil)
                  return
                }
              }
              throw Failure(message: "popover did not appear")
            }
          }
          throw Failure(message: "native label deadline exceeded")
        } catch {
          log("FAIL \(error)")
          testDefaults.removePersistentDomain(forName: preferencesName)
          NSApp.terminate(nil)
        }
      }
    }

    private static func findButton(_ view: NSView?) -> NSStatusBarButton? {
      guard let view else { return nil }
      if let button = view as? NSStatusBarButton { return button }
      return view.subviews.compactMap { findButton($0) }.first
    }

    private static func presentationEvidence(model: AppModel, button: NSStatusBarButton)
      async throws
    {
      try await Task.sleep(nanoseconds: 300_000_000)
      try capturePopover("providers-before")
      let original = model.visibleProviderIDs
      try require(original.count >= 2, "fixture needs two signed-in providers")
      model.moveProvider(original[1], by: -1)
      var expected = original
      expected.swapAt(0, 1)
      try require(model.visibleProviderIDs == expected, "arrow model route did not reorder")
      button.performClick(nil)
      try await Task.sleep(nanoseconds: 200_000_000)
      button.performClick(nil)
      try await Task.sleep(nanoseconds: 300_000_000)
      try require(model.visibleProviderIDs == expected, "popover reopen lost order")
      try capturePopover("providers-reordered-reopened")
      log(
        "PASS presentation: arrow model route \(original) -> \(expected), retained on native popover reopen"
      )

      let ambiguous = ProviderQuota(
        provider: original[0], label: "Synthetic prior sign-in", source: .api, windows: [],
        state: ProviderState(status: .error, stale: false))
      try await refreshFixture([ambiguous], model: model)
      try require(model.visibleProviderIDs == [original[0]], "prior sign-in was hidden")
      try require(model.presentation.signInIsUncertain(ambiguous), "missing ambiguity state")
      try capturePopover("sign-in-unconfirmed")
      let signedOut = ProviderQuota(
        provider: original[0], label: "Synthetic prior sign-in", source: .api, windows: [],
        state: ProviderState(status: .authRequired, stale: false))
      try await refreshFixture([signedOut], model: model)
      try require(model.emptyProviderMessage != nil, "missing signed-out empty state")
      try capturePopover("signed-out-empty")
      log(
        "PASS presentation: transient error retained prior sign-in with unknown quota; auth-required selected empty state"
      )
    }

    private static func refreshFixture(_ providers: [ProviderQuota], model: AppModel) async throws {
      let report = QuotaAxiResponse(generatedAt: "2026-01-01T00:00:00Z", providers: providers)
      try JSONEncoder().encode(report).write(to: directory.appendingPathComponent("fixture.json"))
      await model.refresh()
      try await Task.sleep(nanoseconds: 200_000_000)
    }

    private static func capturePopover(_ name: String) throws {
      guard
        let view = NSApp.windows.first(where: {
          $0.isVisible && ($0.contentView?.bounds.width ?? 0) >= 400
            && ($0.contentView?.bounds.height ?? 0) >= 600
        })?.contentView
      else { throw Failure(message: "no rendered popover for evidence") }
      view.layoutSubtreeIfNeeded()
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw Failure(message: "popover bitmap unavailable")
      }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw Failure(message: "popover PNG unavailable")
      }
      let evidenceDirectory =
        CommandLine.arguments.count == 3
        ? URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true) : directory!
      try png.write(to: evidenceDirectory.appendingPathComponent(name + ".png"))
    }

    private static func pixels(_ button: NSStatusBarButton) throws -> Data {
      try require(button.title.isEmpty && button.isEnabled, "not an enabled ring-only button")
      guard let image = button.image else { throw Failure(message: "native button image=nil") }
      try require(!image.isTemplate, "native image lost original colors")
      guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff)
      else { throw Failure(message: "native image has no pixels") }
      var opaque = 0
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 }
        }
      }
      try require(opaque > 20, "native image is empty")
      try require(
        (bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
          .alphaComponent ?? 1) < 0.1, "native image is not a hollow ring")
      guard let bytes = bitmap.bitmapData else { throw Failure(message: "missing bitmap storage") }
      return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private struct Failure: Error { let message: String }
    private static func require(_ condition: Bool, _ message: String) throws {
      if !condition { throw Failure(message: message) }
    }
    private static func log(_ message: String) {
      let url = directory.appendingPathComponent("result.log")
      let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      try? (previous + message + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
  }
#endif
