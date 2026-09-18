import Foundation

public struct QuotaCollection: Sendable {
  public let report: QuotaAxiResponse
  public let executable: DiscoveredExecutable

  public init(report: QuotaAxiResponse, executable: DiscoveredExecutable) {
    self.report = report
    self.executable = executable
  }
}

public enum QuotaCollectorError: Error, Equatable, LocalizedError, Sendable {
  case executableNotFound
  case process(ProcessRunnerError)
  case invalidResponse
  case unsupportedSchema(Int)

  public var errorDescription: String? {
    switch self {
    case .executableNotFound:
      return "Quota AXI was not found. Choose an installed quota-axi executable to finish setup."
    case .process(let error):
      return error.errorDescription
    case .invalidResponse:
      return "Quota AXI returned data Quota Bar could not read."
    case .unsupportedSchema(let version):
      return
        "Quota AXI returned unsupported schema version \(version); Quota Bar supports versions 3 and 5."
    }
  }
}

public struct QuotaCollector: Sendable {
  public static let defaultTimeout: TimeInterval = 45
  public static let defaultMaximumOutputBytes = 2 * 1_024 * 1_024

  private let discovery: ExecutableDiscovery
  private let runner: BoundedProcessRunner
  private let timeout: TimeInterval
  private let maximumOutputBytes: Int

  public init(
    discovery: ExecutableDiscovery = ExecutableDiscovery(),
    runner: BoundedProcessRunner = BoundedProcessRunner(),
    timeout: TimeInterval = QuotaCollector.defaultTimeout,
    maximumOutputBytes: Int = QuotaCollector.defaultMaximumOutputBytes
  ) {
    self.discovery = discovery
    self.runner = runner
    self.timeout = timeout
    self.maximumOutputBytes = maximumOutputBytes
  }

  public func collect(
    configuredPath: String?,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> QuotaCollection {
    guard
      let executable = discovery.discover(
        configuredPath: configuredPath,
        environment: environment,
        homeDirectory: homeDirectory
      )
    else {
      throw QuotaCollectorError.executableNotFound
    }

    let output: ProcessOutput
    do {
      output = try runner.run(
        executableURL: executable.url,
        arguments: ["--json"],
        environment: childEnvironment(
          base: environment,
          executable: executable,
          homeDirectory: homeDirectory
        ),
        timeout: timeout,
        maximumOutputBytes: maximumOutputBytes,
        acceptedExitCodes: [0, 1]
      )
    } catch let error as ProcessRunnerError {
      throw QuotaCollectorError.process(error)
    } catch {
      throw QuotaCollectorError.process(.launchFailed)
    }

    let report: QuotaAxiResponse
    do {
      report = try JSONDecoder().decode(QuotaAxiResponse.self, from: output.standardOutput)
    } catch QuotaSchemaError.unsupportedVersion(let version) {
      throw QuotaCollectorError.unsupportedSchema(version)
    } catch {
      if output.exitCode != 0 {
        throw QuotaCollectorError.process(.unsuccessfulExit(output.exitCode))
      }
      throw QuotaCollectorError.invalidResponse
    }

    // quota-axi loadQuota exits 1 with a valid report when all providers failed.
    // Consume those structured auth states rather than preserving a signed-in
    // snapshot forever after the last provider signs out. Other failures stay failures.
    if output.exitCode == 1
      && (report.providers.isEmpty
        || report.providers.contains {
          $0.state.status == .fresh || $0.state.status == .stale
        })
    {
      throw QuotaCollectorError.process(.unsuccessfulExit(1))
    }

    return QuotaCollection(report: report, executable: executable)
  }

  private func childEnvironment(
    base: [String: String],
    executable: DiscoveredExecutable,
    homeDirectory: URL
  ) -> [String: String] {
    var environment = base
    var searchPaths = [executable.url.deletingLastPathComponent().path]

    if let nvmBin = nvmBinDirectory(containing: executable.resolvedURL) {
      searchPaths.append(nvmBin)
    }

    searchPaths.append(contentsOf: [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/opt/local/bin",
      homeDirectory.appendingPathComponent(".local/bin").path,
      homeDirectory.appendingPathComponent("bin").path,
      "/usr/bin",
      "/bin",
    ])

    if let inheritedPath = base["PATH"] {
      searchPaths.append(contentsOf: inheritedPath.split(separator: ":").map(String.init))
    }

    var seen = Set<String>()
    environment["PATH"] =
      searchPaths
      .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
      .joined(separator: ":")
    return environment
  }

  private func nvmBinDirectory(containing executable: URL) -> String? {
    let path = executable.path
    let marker = "/.nvm/versions/node/"
    guard let range = path.range(of: marker) else { return nil }
    let prefix = String(path[..<range.upperBound])
    let remainder = path[range.upperBound...]
    guard let version = remainder.split(separator: "/").first, !version.isEmpty else {
      return nil
    }
    return prefix + version + "/bin"
  }
}
