import AppKit
import Foundation
import QuotaBarCore

@MainActor
final class AppModel: ObservableObject {
  static let refreshInterval: TimeInterval = 15 * 60
  static let configuredPathKey = "QuotaAxiExecutablePath"

  @Published private(set) var state: QuotaDisplayState
  @Published private(set) var isRefreshing = false
  @Published private(set) var executableSource: ExecutableSource?

  private let collector: QuotaCollector
  private let cache: FileSnapshotCache
  private let defaults: UserDefaults
  private var refreshLoop: Task<Void, Never>?

  init(
    collector: QuotaCollector = QuotaCollector(),
    cache: FileSnapshotCache = .applicationDefault(),
    defaults: UserDefaults = .standard
  ) {
    self.collector = collector
    self.cache = cache
    self.defaults = defaults
    state = RefreshStateReducer.initial(cachedSnapshot: cache.load())
  }

  deinit {
    refreshLoop?.cancel()
  }

  var headlineSignal: QuotaSignal {
    guard !state.isStale, let report = state.report else { return .neutral }
    return QuotaSignal.forRemaining(
      QuotaSummary.tightestKnown(in: report)?.availability.effectivePercentRemaining
    )
  }

  var headlineAccessibilityLabel: String {
    if state.isStale {
      return "Quota unavailable. Last successful data is stale."
    }
    guard
      let report = state.report,
      let tightest = QuotaSummary.tightestKnown(in: report),
      let percentage = tightest.availability.effectivePercentRemaining
    else {
      return "Quota unavailable. No effective quota is known."
    }
    return
      "Quota \(headlineSignal.accessibilityName). \(percentage.formattedQuotaPercentage) percent remaining."
  }

  var configuredPath: String? {
    defaults.string(forKey: Self.configuredPathKey)
  }

  func start() {
    guard refreshLoop == nil else { return }
    refreshLoop = Task { [weak self] in
      guard let self else { return }
      await self.refresh()
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
        } catch {
          return
        }
        await self.refresh()
      }
    }
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    let collector = self.collector
    let path = configuredPath
    let result = await Task.detached(priority: .utility) {
      Result { try collector.collect(configuredPath: path) }
    }.value

    switch result {
    case .success(let collection):
      let now = Date()
      state = RefreshStateReducer.success(report: collection.report, at: now)
      executableSource = collection.executable.source
      try? cache.save(StoredSnapshot(savedAt: now, report: collection.report))
    case .failure(let error):
      let message =
        (error as? LocalizedError)?.errorDescription
        ?? "Quota AXI could not refresh quota data."
      state = RefreshStateReducer.failure(previous: state, message: message)
    }
  }

  func chooseExecutable() {
    let panel = NSOpenPanel()
    panel.title = "Choose quota-axi"
    panel.message =
      "Choose the installed quota-axi executable. Quota Bar stores only this location."
    panel.prompt = "Choose"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard ExecutableDiscovery().validateConfiguredPath(url.path) != nil else {
      state = RefreshStateReducer.failure(
        previous: state,
        message: "The selected item is not a regular executable file."
      )
      return
    }
    defaults.set(url.path, forKey: Self.configuredPathKey)
    Task { await refresh() }
  }

  func clearConfiguredExecutable() {
    defaults.removeObject(forKey: Self.configuredPathKey)
    Task { await refresh() }
  }

  func quit() {
    NSApplication.shared.terminate(nil)
  }
}

extension QuotaSignal {
  fileprivate var accessibilityName: String {
    switch self {
    case .healthy: return "healthy"
    case .caution: return "caution"
    case .critical: return "critical"
    case .neutral: return "unknown"
    }
  }
}

extension Double {
  var formattedQuotaPercentage: String {
    formatted(.number.precision(.fractionLength(0...2)))
  }
}
