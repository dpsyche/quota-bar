import Foundation
import Testing

@testable import QuotaBarCore

struct SnapshotCacheTests {
  @Test
  func upgradeLoadsOldSnapshotThenRoundTripsCurrentReportAtTheSamePath() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("snapshot-v3.json")
    let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // Construct the old persisted envelope independently of the current encoder.
    let legacyFixture = try #require(Bundle.module.url(forResource: "quota-v3", withExtension: "json"))
    let legacyObject = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyFixture))
    let oldBytes = try JSONSerialization.data(withJSONObject: [
      "savedAt": ISO8601DateFormatter().string(from: savedAt), "report": legacyObject,
    ])
    try oldBytes.write(to: file)
    let cache = FileSnapshotCache(fileURL: file)
    let oldSnapshot = try #require(cache.load())
    #expect(oldSnapshot.savedAt == savedAt)
    #expect(oldSnapshot.report.schemaVersion == 3)
    #expect(oldSnapshot.report.providers.first?.label == "Codex")
    #expect(oldSnapshot.report.providers.first?.source == .cliRPC)
    #expect(oldSnapshot.report.providers.first?.state.sourcesTried == ["cli-rpc"])
    #expect(oldSnapshot.report.providers.first?.state.refreshedAt == "2026-01-15T11:59:58.000Z")
    let startup = RefreshStateReducer.initial(cachedSnapshot: oldSnapshot)
    #expect(startup.isStale)
    #expect(startup.lastSuccessfulRefresh == savedAt)
    #expect(try Data(contentsOf: file) == oldBytes)  // Loading never rewrites the old cache.

    let fixture = try #require(Bundle.module.url(forResource: "quota-v5", withExtension: "json"))
    let current = try JSONDecoder().decode(QuotaAxiResponse.self, from: Data(contentsOf: fixture))
    let nextSavedAt = savedAt.addingTimeInterval(60)
    try cache.save(StoredSnapshot(savedAt: nextSavedAt, report: current))
    let reopened = try #require(FileSnapshotCache(fileURL: file).load())
    #expect(reopened.savedAt == nextSavedAt)
    #expect(reopened.report.schemaVersion == 5)
    #expect(reopened.report.providers.first?.label == nil)
    #expect(reopened.report.providers.first?.source == nil)
    #expect(reopened.report.providers.first?.state.sourcesTried == nil)
    #expect(reopened.report.providers.first?.quotaSemantics?.description == nil)
    #expect(QuotaSummary.tightestKnown(in: reopened.report)?.availability.effectivePercentRemaining == 47)
    #expect(QuotaSummary.knownForDisplay(for: reopened.report.providers[1]) == nil)
    #expect(reopened.report.providers[1].windows.last?.percentRemaining == nil)
    #expect(reopened.report.providers[2].state.stale)
    #expect(reopened.report.providers[2].state.authStatus == .expiredRefreshable)
    #expect(reopened.report.providers[3].state.status == .authRequired)
    #expect(RefreshStateReducer.initial(cachedSnapshot: reopened).isStale)
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  }

  @Test
  func unsupportedOrMalformedCacheIsIgnoredWithoutRewritingIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("snapshot-v3.json")
    let cache = FileSnapshotCache(fileURL: file)
    #expect(cache.load() == nil)
    for json in [
      "{\"savedAt\":\"2026-01-01T00:00:00Z\",\"report\":{\"schemaVersion\":99}}",
      "{\"savedAt\":\"2026-01-01T00:00:00Z\",\"report\":{\"schemaVersion\":5}}",
      "not-json",
    ] {
      let bytes = Data(json.utf8)
      try bytes.write(to: file)
      #expect(cache.load() == nil)
      #expect(try Data(contentsOf: file) == bytes)
    }
  }
}
