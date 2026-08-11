import Foundation

public enum ExecutableSource: Equatable, Sendable {
  case configured
  case inheritedPath
  case commonLocation
  case nvm
}

public struct DiscoveredExecutable: Equatable, Sendable {
  /// The candidate path is retained so an npm/NVM bin directory can be placed on PATH.
  public let url: URL
  public let resolvedURL: URL
  public let source: ExecutableSource

  public init(url: URL, resolvedURL: URL, source: ExecutableSource) {
    self.url = url
    self.resolvedURL = resolvedURL
    self.source = source
  }
}

public struct ExecutableDiscovery: Sendable {
  public init() {}

  public func discover(
    configuredPath: String?,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    commonDirectories: [URL]? = nil
  ) -> DiscoveredExecutable? {
    var candidates: [(URL, ExecutableSource)] = []

    if let configuredPath, !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let expanded = (configuredPath as NSString).expandingTildeInPath
      candidates.append((URL(fileURLWithPath: expanded), .configured))
    }

    for directory in pathDirectories(environment["PATH"]) {
      candidates.append((directory.appendingPathComponent("quota-axi"), .inheritedPath))
    }

    let searchDirectories =
      commonDirectories ?? [
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/opt/local/bin", isDirectory: true),
        homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
        homeDirectory.appendingPathComponent("bin", isDirectory: true),
        homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true),
        homeDirectory.appendingPathComponent("Library/pnpm", isDirectory: true),
      ]
    candidates.append(
      contentsOf: searchDirectories.map {
        ($0.appendingPathComponent("quota-axi"), .commonLocation)
      })

    candidates.append(contentsOf: nvmCandidates(homeDirectory: homeDirectory).map { ($0, .nvm) })

    var seen = Set<String>()
    for (candidate, source) in candidates {
      let standardized = candidate.standardizedFileURL
      guard standardized.path.hasPrefix("/"), seen.insert(standardized.path).inserted else {
        continue
      }
      if let executable = validate(url: standardized, source: source) {
        return executable
      }
    }
    return nil
  }

  public func validateConfiguredPath(_ path: String) -> DiscoveredExecutable? {
    let expanded = (path as NSString).expandingTildeInPath
    return validate(url: URL(fileURLWithPath: expanded).standardizedFileURL, source: .configured)
  }

  private func validate(url: URL, source: ExecutableSource) -> DiscoveredExecutable? {
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
    guard
      resolved.path.hasPrefix("/"),
      (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
      FileManager.default.isExecutableFile(atPath: resolved.path)
    else { return nil }

    return DiscoveredExecutable(url: url, resolvedURL: resolved, source: source)
  }

  private func pathDirectories(_ path: String?) -> [URL] {
    guard let path else { return [] }
    return
      path
      .split(separator: ":", omittingEmptySubsequences: false)
      .map(String.init)
      .filter { $0.hasPrefix("/") }
      .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
  }

  private func nvmCandidates(homeDirectory: URL) -> [URL] {
    let versions = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: versions,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    return
      entries
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .sorted {
        compareNodeVersions($0.lastPathComponent, $1.lastPathComponent) == .orderedDescending
      }
      .map { $0.appendingPathComponent("bin/quota-axi") }
  }

  private func compareNodeVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = numericVersion(lhs)
    let right = numericVersion(rhs)
    let count = max(left.count, right.count)

    for index in 0..<count {
      let leftPart = index < left.count ? left[index] : 0
      let rightPart = index < right.count ? right[index] : 0
      if leftPart < rightPart { return .orderedAscending }
      if leftPart > rightPart { return .orderedDescending }
    }
    return lhs.compare(rhs, options: .numeric)
  }

  private func numericVersion(_ value: String) -> [Int] {
    value
      .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
      .split(separator: ".")
      .map { Int($0.prefix { $0.isNumber }) ?? 0 }
  }
}
