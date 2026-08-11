import Foundation
import Testing

@testable import QuotaBarCore

struct QuotaCollectorFailureTests {
  @Test
  func collectorMapsNonzeroExitToProcessFailure() throws {
    let temporaryDirectory = try CollectorTemporaryDirectory()
    let executable = try makeExecutable(in: temporaryDirectory.url, body: "exit 7")
    let collector = QuotaCollector(timeout: 1, maximumOutputBytes: 1_024)

    do {
      _ = try collector.collect(
        configuredPath: executable.path,
        environment: ["PATH": "/usr/bin:/bin"],
        homeDirectory: temporaryDirectory.url
      )
      Issue.record("Expected a process failure")
    } catch {
      #expect(error as? QuotaCollectorError == .process(.unsuccessfulExit(7)))
    }
  }

  @Test
  func collectorMapsHungExecutableToTimeout() throws {
    let temporaryDirectory = try CollectorTemporaryDirectory()
    let executable = try makeExecutable(in: temporaryDirectory.url, body: "/bin/sleep 2")
    let collector = QuotaCollector(timeout: 0.05, maximumOutputBytes: 1_024)

    do {
      _ = try collector.collect(
        configuredPath: executable.path,
        environment: ["PATH": "/usr/bin:/bin"],
        homeDirectory: temporaryDirectory.url
      )
      Issue.record("Expected a collector timeout")
    } catch {
      #expect(error as? QuotaCollectorError == .process(.timedOut))
    }
  }

  @Test
  func collectorRejectsSuccessfulButInvalidJSON() throws {
    let temporaryDirectory = try CollectorTemporaryDirectory()
    let executable = try makeExecutable(in: temporaryDirectory.url, body: "printf 'not-json'")
    let collector = QuotaCollector(timeout: 1, maximumOutputBytes: 1_024)

    do {
      _ = try collector.collect(
        configuredPath: executable.path,
        environment: ["PATH": "/usr/bin:/bin"],
        homeDirectory: temporaryDirectory.url
      )
      Issue.record("Expected an invalid-response error")
    } catch {
      #expect(error as? QuotaCollectorError == .invalidResponse)
    }
  }

  private func makeExecutable(in directory: URL, body: String) throws -> URL {
    let url = directory.appendingPathComponent("quota-axi-\(UUID().uuidString)")
    let script = "#!/bin/sh\n\(body)\n"
    let created = FileManager.default.createFile(
      atPath: url.path,
      contents: Data(script.utf8),
      attributes: [.posixPermissions: 0o755]
    )
    #expect(created)
    return url
  }
}

private final class CollectorTemporaryDirectory {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuotaBarCollectorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}
