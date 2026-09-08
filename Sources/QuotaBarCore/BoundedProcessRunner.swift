import Darwin
import Foundation

public struct ProcessOutput: Equatable, Sendable {
  public let standardOutput: Data
  public let standardError: Data
  public let exitCode: Int32

  public init(standardOutput: Data, standardError: Data, exitCode: Int32) {
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.exitCode = exitCode
  }
}

public enum ProcessRunnerError: Error, Equatable, LocalizedError, Sendable {
  case launchFailed
  case timedOut
  case outputLimitExceeded
  case unsuccessfulExit(Int32)

  public var errorDescription: String? {
    switch self {
    case .launchFailed:
      return "The collector could not be launched."
    case .timedOut:
      return "The collector did not finish before the time limit."
    case .outputLimitExceeded:
      return "The collector returned more data than Quota Bar can safely process."
    case .unsuccessfulExit(let code):
      return "The collector exited with status \(code)."
    }
  }
}

public struct BoundedProcessRunner: Sendable {
  public init() {}

  public func run(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]? = nil,
    timeout: TimeInterval,
    maximumOutputBytes: Int,
    acceptedExitCodes: Set<Int32> = [0]
  ) throws -> ProcessOutput {
    precondition(timeout > 0)
    precondition(maximumOutputBytes > 0)

    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let termination = DispatchSemaphore(value: 0)
    let accumulator = OutputAccumulator(limit: maximumOutputBytes)
    let controller = ProcessController(process: process)

    process.executableURL = executableURL
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    if let environment { process.environment = environment }
    process.terminationHandler = { _ in termination.signal() }

    installReadHandler(
      on: outputPipe.fileHandleForReading,
      stream: .standardOutput,
      accumulator: accumulator,
      controller: controller
    )
    installReadHandler(
      on: errorPipe.fileHandleForReading,
      stream: .standardError,
      accumulator: accumulator,
      controller: controller
    )

    do {
      try process.run()
    } catch {
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
      throw ProcessRunnerError.launchFailed
    }

    let deadline = DispatchTime.now() + timeout
    if termination.wait(timeout: deadline) == .timedOut {
      controller.terminate()
      if termination.wait(timeout: .now() + 1) == .timedOut {
        controller.kill()
        _ = termination.wait(timeout: .now() + 1)
      }
      closeReadHandlers(outputPipe: outputPipe, errorPipe: errorPipe)
      throw ProcessRunnerError.timedOut
    }

    // Give readability handlers a brief chance to consume the final bytes after EOF.
    accumulator.waitForReaders(timeout: 1)
    closeReadHandlers(outputPipe: outputPipe, errorPipe: errorPipe)

    if accumulator.exceededLimit {
      throw ProcessRunnerError.outputLimitExceeded
    }
    if !acceptedExitCodes.contains(process.terminationStatus) {
      throw ProcessRunnerError.unsuccessfulExit(process.terminationStatus)
    }

    return ProcessOutput(
      standardOutput: accumulator.standardOutput,
      standardError: accumulator.standardError,
      exitCode: process.terminationStatus
    )
  }

  private func installReadHandler(
    on handle: FileHandle,
    stream: OutputStream,
    accumulator: OutputAccumulator,
    controller: ProcessController
  ) {
    accumulator.readerStarted()
    handle.readabilityHandler = { readableHandle in
      let data = readableHandle.availableData
      guard !data.isEmpty else {
        readableHandle.readabilityHandler = nil
        accumulator.readerFinished()
        return
      }
      if !accumulator.append(data, to: stream) {
        controller.terminate()
      }
    }
  }

  private func closeReadHandlers(outputPipe: Pipe, errorPipe: Pipe) {
    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil
    try? outputPipe.fileHandleForReading.close()
    try? errorPipe.fileHandleForReading.close()
  }
}

private enum OutputStream {
  case standardOutput
  case standardError
}

private final class OutputAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private let limit: Int
  private var output = Data()
  private var error = Data()
  private var didExceedLimit = false
  private let readers = DispatchGroup()

  init(limit: Int) {
    self.limit = limit
  }

  func readerStarted() {
    readers.enter()
  }

  func readerFinished() {
    readers.leave()
  }

  func waitForReaders(timeout: TimeInterval) {
    _ = readers.wait(timeout: .now() + timeout)
  }

  func append(_ data: Data, to stream: OutputStream) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    let storedCount = output.count + error.count
    let available = max(0, limit - storedCount)
    if available > 0 {
      let retained = data.prefix(available)
      switch stream {
      case .standardOutput:
        output.append(retained)
      case .standardError:
        error.append(retained)
      }
    }
    if data.count > available {
      didExceedLimit = true
    }
    return !didExceedLimit
  }

  var standardOutput: Data {
    lock.withLock { output }
  }

  var standardError: Data {
    lock.withLock { error }
  }

  var exceededLimit: Bool {
    lock.withLock { didExceedLimit }
  }
}

private final class ProcessController: @unchecked Sendable {
  private let process: Process
  private let lock = NSLock()

  init(process: Process) {
    self.process = process
  }

  func terminate() {
    lock.withLock {
      guard process.isRunning else { return }
      process.terminate()
    }
  }

  func kill() {
    lock.withLock {
      guard process.isRunning else { return }
      Darwin.kill(process.processIdentifier, SIGKILL)
    }
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ operation: () -> T) -> T {
    lock()
    defer { unlock() }
    return operation()
  }
}
