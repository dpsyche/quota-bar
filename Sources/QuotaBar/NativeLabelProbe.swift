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
