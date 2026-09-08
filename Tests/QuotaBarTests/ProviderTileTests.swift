import AppKit
import QuotaBarCore
import Testing

@testable import QuotaBar

@MainActor
struct ProviderTileTests {
  @Test
  func refreshRelaunchAndArrowMovesUseTheSameSavedOrder() async throws {
    let lab = try TileLab()
    defer { lab.remove() }
    try lab.report([provider("a"), provider("b"), provider("c")])
    let model = lab.model()
    await model.refresh()
    #expect(model.visibleProviderIDs == ["a", "b", "c"])
    model.moveProvider("c", by: -1)
    #expect(model.visibleProviderIDs == ["a", "c", "b"])
    model.moveProvider("a", by: -1)
    #expect(model.visibleProviderIDs == ["a", "c", "b"])
    model.moveProvider("b", by: 1)
    model.moveProvider("missing", by: -1)
    #expect(model.visibleProviderIDs == ["a", "c", "b"])
    try lab.report([provider("c"), provider("a"), provider("b", status: .authRequired)])
    await model.refresh()
    #expect(model.visibleProviderIDs == ["a", "c"])
    let relaunched = lab.model()
    #expect(relaunched.visibleProviderIDs == ["a", "c"])
    #expect(relaunched.state.isStale)
    try lab.report([provider("b"), provider("d"), provider("a"), provider("c")])
    await relaunched.refresh()
    #expect(relaunched.visibleProviderIDs == ["a", "c", "b", "d"])
  }

  @Test
  func allSignedOutExitOneShowsEmptyStateThenSigningInRestoresTiles() async throws {
    let lab = try TileLab()
    defer { lab.remove() }
    try lab.report([provider("a")])
    let model = lab.model()
    await model.refresh()
    #expect(model.emptyProviderMessage == nil)
    try lab.report([provider("a", status: .authRequired)], exitCode: 1)
    await model.refresh()
    #expect(model.visibleProviders.isEmpty)
    #expect(model.emptyProviderMessage == ProviderPresentation.emptyMessage)
    #expect(model.state.failureMessage == nil)
    #expect(model.configuredPath != nil)  // Setup controls remain available.
    #expect(model.headlineSignal == .neutral)
    #expect(!model.isRefreshing)
    try lab.report([provider("a")])
    await model.refresh()
    #expect(model.visibleProviderIDs == ["a"])
    #expect(model.emptyProviderMessage == nil)
  }

  @Test
  func providerAndProcessFailuresKeepKnownSignInButNotInventedQuota() async throws {
    let lab = try TileLab()
    defer { lab.remove() }
    try lab.report([provider("known")])
    let model = lab.model()
    await model.refresh()
    try lab.report(
      [provider("known", status: .error), provider("unknown", status: .error)], exitCode: 1)
    await model.refresh()
    #expect(model.visibleProviderIDs == ["known"])
    #expect(model.presentation.signInIsUncertain(try #require(model.visibleProviders.first)))
    #expect(model.headlineSignal == .neutral)
    try "#!/bin/sh\nexit 7\n".write(to: lab.executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: lab.executable.path)
    await model.refresh()
    #expect(model.visibleProviderIDs == ["known"])
    #expect(model.state.isStale)
    #expect(model.state.failureMessage != nil)
    #expect(model.headlineSignal == .neutral)
  }

  @Test
  func filteringAndReorderingNeverFeedHeadlineCalculations() async throws {
    let lab = try TileLab()
    defer { lab.remove() }
    let unknownAuth = ProviderQuota(
      provider: "unconfirmed", label: "Synthetic", source: .api, windows: [],
      quotaSemantics: QuotaSemantics(
        status: .known, description: "Synthetic",
        effectiveAvailability: [
          EffectiveAvailability(
            scope: "all", status: .known,
            effectivePercentRemaining: 15)
        ]),
      state: ProviderState(status: .fresh, stale: false, authStatus: .unusable))
    try lab.report([provider("a"), unknownAuth, provider("b")])
    let model = lab.model()
    await model.refresh()
    #expect(model.visibleProviderIDs == ["a", "b"])
    #expect(model.headlineSignal == .critical)
    model.moveProvider("a", by: 1)
    #expect(model.visibleProviderIDs == ["b", "a"])
    #expect(model.headlineSignal == .critical)
    #expect(model.state.report?.providers.map(\.provider) == ["a", "unconfirmed", "b"])
  }

  private func provider(_ id: String, status: ProviderStatus = .fresh) -> ProviderQuota {
    ProviderQuota(
      provider: id, label: "Synthetic \(id)", source: .api, windows: [],
      state: ProviderState(status: status, stale: false))
  }
}

private struct TileLab {
  let directory: URL
  let name = "local.QuotaBar.TileTests." + UUID().uuidString
  let defaults: UserDefaults
  var executable: URL { directory.appendingPathComponent("collector") }

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defaults = UserDefaults(suiteName: name)!
  }

  @MainActor func model() -> AppModel {
    defaults.set(executable.path, forKey: AppModel.configuredPathKey)
    return AppModel(
      cache: FileSnapshotCache(fileURL: directory.appendingPathComponent("snapshot.json")),
      defaults: UserDefaults(suiteName: name)!)
  }

  func report(_ providers: [ProviderQuota], exitCode: Int = 0) throws {
    let report = QuotaAxiResponse(generatedAt: "2026-01-01T00:00:00Z", providers: providers)
    try JSONEncoder().encode(report).write(to: directory.appendingPathComponent("fixture.json"))
    try "#!/bin/sh\n/bin/cat '\(directory.path)/fixture.json'\nexit \(exitCode)\n".write(
      to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
  }

  func remove() {
    defaults.removePersistentDomain(forName: name)
    try? FileManager.default.removeItem(at: directory)
  }
}
