import Foundation

public struct StoredSnapshot: Codable, Sendable {
  public let savedAt: Date
  public let report: QuotaAxiResponse

  public init(savedAt: Date, report: QuotaAxiResponse) {
    self.savedAt = savedAt
    self.report = report
  }
}

public struct QuotaDisplayState: Sendable {
  public let report: QuotaAxiResponse?
  public let lastSuccessfulRefresh: Date?
  public let isStale: Bool
  public let failureMessage: String?

  public init(
    report: QuotaAxiResponse?,
    lastSuccessfulRefresh: Date?,
    isStale: Bool,
    failureMessage: String?
  ) {
    self.report = report
    self.lastSuccessfulRefresh = lastSuccessfulRefresh
    self.isStale = isStale
    self.failureMessage = failureMessage
  }
}

public enum RefreshStateReducer {
  public static func initial(cachedSnapshot: StoredSnapshot?) -> QuotaDisplayState {
    guard let cachedSnapshot else {
      return QuotaDisplayState(
        report: nil,
        lastSuccessfulRefresh: nil,
        isStale: false,
        failureMessage: nil
      )
    }
    return QuotaDisplayState(
      report: cachedSnapshot.report,
      lastSuccessfulRefresh: cachedSnapshot.savedAt,
      isStale: true,
      failureMessage: nil
    )
  }

  public static func success(report: QuotaAxiResponse, at date: Date) -> QuotaDisplayState {
    QuotaDisplayState(
      report: report,
      lastSuccessfulRefresh: date,
      isStale: false,
      failureMessage: nil
    )
  }

  public static func failure(
    previous: QuotaDisplayState,
    message: String
  ) -> QuotaDisplayState {
    QuotaDisplayState(
      report: previous.report,
      lastSuccessfulRefresh: previous.lastSuccessfulRefresh,
      isStale: previous.report != nil,
      failureMessage: message
    )
  }
}

public final class FileSnapshotCache: @unchecked Sendable {
  private let fileURL: URL
  private let fileManager: FileManager

  public init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  public static func applicationDefault(fileManager: FileManager = .default) -> FileSnapshotCache {
    let applicationSupport =
      fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    // Retain the original filename so upgrades still find existing v3 snapshots.
    // The report's versioned decoder also accepts current snapshots at this path.
    let fileURL =
      applicationSupport
      .appendingPathComponent("QuotaBar", isDirectory: true)
      .appendingPathComponent("snapshot-v3.json")
    return FileSnapshotCache(fileURL: fileURL, fileManager: fileManager)
  }

  public func load() -> StoredSnapshot? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(StoredSnapshot.self, from: data)
  }

  public func save(_ snapshot: StoredSnapshot) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)
    try data.write(to: fileURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}
