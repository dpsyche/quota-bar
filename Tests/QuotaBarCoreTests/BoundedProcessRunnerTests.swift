import Foundation
import Testing

@testable import QuotaBarCore

struct BoundedProcessRunnerTests {
  private let runner = BoundedProcessRunner()

  @Test
  func successfulProcessReturnsCapturedOutput() throws {
    let output = try runner.run(
      executableURL: URL(fileURLWithPath: "/bin/echo"),
      arguments: ["quota-ok"],
      timeout: 2,
      maximumOutputBytes: 1_024
    )

    #expect(String(decoding: output.standardOutput, as: UTF8.self) == "quota-ok\n")
    #expect(output.exitCode == 0)
  }

  @Test
  func nonzeroProcessExitIsReportedWithoutReturningPathologicalOutput() {
    do {
      _ = try runner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/false"),
        arguments: [],
        timeout: 2,
        maximumOutputBytes: 1_024
      )
      Issue.record("Expected a nonzero-exit error")
    } catch {
      #expect(error as? ProcessRunnerError == .unsuccessfulExit(1))
    }
  }

  @Test
  func hungProcessIsTerminatedAtTimeout() {
    let started = Date()

    do {
      _ = try runner.run(
        executableURL: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["2"],
        timeout: 0.05,
        maximumOutputBytes: 1_024
      )
      Issue.record("Expected a timeout error")
    } catch {
      #expect(error as? ProcessRunnerError == .timedOut)
    }

    #expect(Date().timeIntervalSince(started) < 1.5)
  }

  @Test
  func outputIsBoundedAndPathologicalProducerIsTerminated() {
    do {
      _ = try runner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
        arguments: [],
        timeout: 2,
        maximumOutputBytes: 1_024
      )
      Issue.record("Expected an output-limit error")
    } catch {
      #expect(error as? ProcessRunnerError == .outputLimitExceeded)
    }
  }
}
