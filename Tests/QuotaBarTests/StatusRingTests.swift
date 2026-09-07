import AppKit
import QuotaBarCore
import Testing
@testable import QuotaBar

@MainActor
struct StatusRingTests {
  @Test
  func colorsAndStrokeBoundsAtBothScales() throws {
    for (signal, expected) in [
      (QuotaSignal.healthy, [101.0, 214, 163]),
      (.caution, [244.0, 201, 107]),
      (.critical, [255.0, 127, 135]),
      (.neutral, [139.0, 145, 166]),
    ] {
      let image = StatusRingImage.make(signal: signal)
      #expect(!image.isTemplate)
      #expect(image.size == NSSize(width: 20, height: 18))
      let representations = image.representations.compactMap { $0 as? NSBitmapImageRep }
      #expect(representations.count == 2)
      for (index, bitmap) in representations.enumerated() {
        let scale = index + 1
        #expect(bitmap.pixelsWide == 20 * scale)
        #expect(bitmap.pixelsHigh == 18 * scale)
        let sample = try #require(bitmap.colorAt(x: 10 * scale, y: 2 * scale))
        let rgb = try #require(sample.usingColorSpace(.deviceRGB))
        #expect(rgb.alphaComponent > 0.9)
        for (actual, value) in zip([rgb.redComponent, rgb.greenComponent, rgb.blueComponent], expected) {
          #expect(abs(actual - value / 255) < 0.02)
        }
        #expect(bitmap.colorAt(x: 10 * scale, y: 9 * scale)?.alphaComponent == 0)
        // No clipped stroke on any canvas edge, including antialiasing.
        for x in 0..<bitmap.pixelsWide {
          #expect(bitmap.colorAt(x: x, y: 0)?.alphaComponent == 0)
          #expect(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1)?.alphaComponent == 0)
        }
        for y in 0..<bitmap.pixelsHigh {
          #expect(bitmap.colorAt(x: 0, y: y)?.alphaComponent == 0)
          #expect(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: y)?.alphaComponent == 0)
        }
      }
    }
  }

  @Test
  func headlineUsesNeutralForMissingStaleAndAuthRequired() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = FileSnapshotCache(fileURL: directory.appendingPathComponent("snapshot.json"))
    let defaults = try #require(UserDefaults(suiteName: "local.QuotaBar.UnitTests.\(UUID().uuidString)"))
    let empty = AppModel(cache: cache, defaults: defaults)
    #expect(empty.headlineSignal == .neutral)
    #expect(empty.headlineAccessibilityLabel.contains("No effective quota is known"))
    let provider = ProviderQuota(
      provider: "synthetic", label: "Synthetic", source: .api, windows: [],
      quotaSemantics: QuotaSemantics(status: .known, description: "Synthetic",
        effectiveAvailability: [EffectiveAvailability(scope: "all", status: .known,
          effectivePercentRemaining: 0)]),
      state: ProviderState(status: .authRequired, stale: false, sourcesTried: ["test"]))
    let report = QuotaAxiResponse(generatedAt: "2026-01-01T00:00:00Z", providers: [provider])
    #expect(QuotaSummary.tightestKnown(in: report) == nil)
    #expect(QuotaSignal.forRemaining(QuotaSummary.tightestKnown(in: report)?
      .availability.effectivePercentRemaining) == .neutral)
    let current = ProviderQuota(
      provider: "synthetic", label: "Synthetic", source: .api, windows: [],
      quotaSemantics: provider.quotaSemantics,
      state: ProviderState(status: .fresh, stale: false, sourcesTried: ["test"]))
    let knownReport = QuotaAxiResponse(
      generatedAt: "2026-01-01T00:00:00Z", providers: [current])
    #expect(QuotaSummary.tightestKnown(in: knownReport)?.availability.effectivePercentRemaining == 0)
    try cache.save(StoredSnapshot(savedAt: Date(timeIntervalSince1970: 0), report: knownReport))
    let stale = AppModel(cache: cache, defaults: defaults)
    #expect(stale.headlineSignal == .neutral)
    #expect(stale.headlineAccessibilityLabel.contains("stale"))
  }
}
