import Foundation
import Testing

@testable import QuotaBarCore

// Process waits are blocking; serialize this suite to avoid saturating the test executor.
@Suite(.serialized)
struct QuotaCollectorFailureTests {
  @Test
  func collectorMapsNonzeroExitToProcessFailure() throws {
    let temporaryDirectory = try CollectorTemporaryDirectory()
    let executable = try makeExecutable(in: temporaryDirectory.url, body: "exit 7")
    let collector = QuotaCollector(timeout: 10, maximumOutputBytes: 1_024)

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
    let collector = QuotaCollector(timeout: 10, maximumOutputBytes: 1_024)

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

  @Test
  func exitOneRequiresACompleteAllFailedSupportedSchemaReport() throws {
    let directory = try CollectorTemporaryDirectory()
    for (body, expected) in [
      ("printf 'not-json'; exit 1", QuotaCollectorError.process(.unsuccessfulExit(1))),
      (
        "printf '%s' '{\"schemaVersion\":3,\"generatedAt\":\"synthetic\",\"providers\":[]}'; exit 1",
        .process(.unsuccessfulExit(1))
      ),
      (
        "printf '%s' '{\"schemaVersion\":4,\"generatedAt\":\"synthetic\",\"providers\":[{\"provider\":\"a\",\"label\":\"A\",\"source\":\"api\",\"windows\":[],\"state\":{\"status\":\"auth_required\",\"stale\":false,\"sourcesTried\":[]}}]}'; exit 1",
        .unsupportedSchema(4)
      ),
      (
        "printf '%s' '{\"schemaVersion\":3,\"generatedAt\":\"synthetic\",\"providers\":[{\"provider\":\"a\",\"label\":\"A\",\"source\":\"api\",\"windows\":[],\"state\":{\"status\":\"fresh\",\"stale\":false,\"sourcesTried\":[]}}]}'; exit 1",
        .process(.unsuccessfulExit(1))
      ),
    ] {
      let executable = try makeExecutable(in: directory.url, body: body)
      do {
        _ = try QuotaCollector(timeout: 10).collect(configuredPath: executable.path)
        Issue.record("Expected rejection")
      } catch {
        #expect(error as? QuotaCollectorError == expected)
      }
    }
  }

  @Test
  func collectorUsesOnlyJSONAndConsumesCurrentDefaultOutput() throws {
    let directory = try CollectorTemporaryDirectory()
    let fixture = try #require(Bundle.module.url(forResource: "quota-v5", withExtension: "json"))
    let executable = try makeExecutable(
      in: directory.url,
      body: """
        [ "$#" = 1 ] && [ "$1" = --json ] || exit 7
        /bin/cat '\(fixture.path)'
        """)
    let collection = try QuotaCollector(timeout: 10).collect(
      configuredPath: executable.path,
      environment: ["PATH": "/usr/bin:/bin"],
      homeDirectory: directory.url)
    #expect(collection.report.schemaVersion == 5)
    #expect(collection.report.providers.first?.label == nil)
    #expect(QuotaSummary.tightestKnown(in: collection.report)?.providerID == "codex")
  }

  @Test(arguments: [0, 1])
  func incompatibleFutureBodyReportsVersionRatherThanUnreadableData(exitCode: Int) throws {
    let directory = try CollectorTemporaryDirectory()
    let executable = try makeExecutable(
      in: directory.url,
      body: "printf '%s' '{\"schemaVersion\":99,\"providers\":{}}'; exit \(exitCode)")
    do {
      _ = try QuotaCollector(timeout: 10).collect(configuredPath: executable.path)
      Issue.record("Expected explicit unsupported-version error")
    } catch {
      #expect(error as? QuotaCollectorError == .unsupportedSchema(99))
      #expect(
        (error as? LocalizedError)?.errorDescription
          == "Quota AXI returned unsupported schema version 99; Quota Bar supports versions 3 and 5.")
    }
  }

  @Test(arguments: [3, 5])
  func allFailedExitOneStillConsumesStructuredAuthState(version: Int) throws {
    let directory = try CollectorTemporaryDirectory()
    let executable = try makeExecutable(
      in: directory.url,
      body: """
        printf '%s' '{"schemaVersion":\(version),"generatedAt":"synthetic","providers":[{"provider":"synthetic","windows":[],"state":{"status":"auth_required","stale":false,"authStatus":"unusable"}}]}'
        exit 1
        """)
    let report = try QuotaCollector(timeout: 10).collect(configuredPath: executable.path).report
    #expect(report.providers.first?.state.status == .authRequired)
    #expect(QuotaSummary.tightestKnown(in: report) == nil)
  }

  @Test(arguments: [0, 1, 7])
  func supportedVersionWithMalformedBodyRemainsAFailure(exitCode: Int) throws {
    let directory = try CollectorTemporaryDirectory()
    let executable = try makeExecutable(
      in: directory.url,
      body: "printf '%s' '{\"schemaVersion\":5,\"generatedAt\":\"synthetic\",\"providers\":{}}'; exit \(exitCode)")
    do {
      _ = try QuotaCollector(timeout: 10).collect(configuredPath: executable.path)
      Issue.record("Expected body decoding or process failure")
    } catch {
      let expected: QuotaCollectorError =
        exitCode == 0 ? .invalidResponse : .process(.unsuccessfulExit(Int32(exitCode)))
      #expect(error as? QuotaCollectorError == expected)
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
