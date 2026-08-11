import Foundation
import Testing

@testable import QuotaBarCore

struct ExecutableDiscoveryTests {
  @Test
  func configuredExecutableTakesPriorityOverInheritedPath() throws {
    let temporaryDirectory = try TemporaryDirectory()
    let configured = temporaryDirectory.url.appendingPathComponent("configured/quota-axi")
    let inherited = temporaryDirectory.url.appendingPathComponent("path/quota-axi")
    try makeExecutable(at: configured)
    try makeExecutable(at: inherited)

    let result = ExecutableDiscovery().discover(
      configuredPath: configured.path,
      environment: ["PATH": inherited.deletingLastPathComponent().path],
      homeDirectory: temporaryDirectory.url,
      commonDirectories: []
    )

    #expect(result?.url == configured.standardizedFileURL)
    #expect(result?.source == .configured)
  }

  @Test
  func invalidConfiguredCandidateFallsBackToExecutableOnPath() throws {
    let temporaryDirectory = try TemporaryDirectory()
    let invalid = temporaryDirectory.url.appendingPathComponent("invalid/quota-axi")
    let inherited = temporaryDirectory.url.appendingPathComponent("path/quota-axi")
    try makeFile(at: invalid, executable: false)
    try makeExecutable(at: inherited)

    let result = ExecutableDiscovery().discover(
      configuredPath: invalid.path,
      environment: ["PATH": inherited.deletingLastPathComponent().path],
      homeDirectory: temporaryDirectory.url,
      commonDirectories: []
    )

    #expect(result?.url == inherited.standardizedFileURL)
    #expect(result?.source == .inheritedPath)
  }

  @Test
  func directoriesAreRejectedEvenWhenSearchable() throws {
    let temporaryDirectory = try TemporaryDirectory()
    let candidate = temporaryDirectory.url.appendingPathComponent("quota-axi", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)

    #expect(ExecutableDiscovery().validateConfiguredPath(candidate.path) == nil)
  }

  @Test
  func executableSymlinkIsAcceptedAfterValidatingRegularTarget() throws {
    let temporaryDirectory = try TemporaryDirectory()
    let target = temporaryDirectory.url.appendingPathComponent("package/quota-axi.js")
    let link = temporaryDirectory.url.appendingPathComponent("bin/quota-axi")
    try makeExecutable(at: target)
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let result = ExecutableDiscovery().validateConfiguredPath(link.path)

    #expect(result?.url == link.standardizedFileURL)
    #expect(result?.resolvedURL == target.standardizedFileURL)
  }

  @Test
  func newestNVMNodeInstallationIsSelectedDeterministically() throws {
    let temporaryDirectory = try TemporaryDirectory()
    let old = temporaryDirectory.url.appendingPathComponent(
      ".nvm/versions/node/v20.19.0/bin/quota-axi")
    let newest = temporaryDirectory.url.appendingPathComponent(
      ".nvm/versions/node/v22.23.2/bin/quota-axi")
    let middle = temporaryDirectory.url.appendingPathComponent(
      ".nvm/versions/node/v22.9.0/bin/quota-axi")
    try makeExecutable(at: old)
    try makeExecutable(at: newest)
    try makeExecutable(at: middle)

    let result = ExecutableDiscovery().discover(
      configuredPath: nil,
      environment: ["PATH": ""],
      homeDirectory: temporaryDirectory.url,
      commonDirectories: []
    )

    #expect(result?.url == newest.standardizedFileURL)
    #expect(result?.source == .nvm)
  }

  private func makeExecutable(at url: URL) throws {
    try makeFile(at: url, executable: true)
  }

  private func makeFile(at url: URL, executable: Bool) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let created = FileManager.default.createFile(
      atPath: url.path,
      contents: Data("#!/bin/sh\nexit 0\n".utf8),
      attributes: [.posixPermissions: executable ? 0o755 : 0o644]
    )
    #expect(created)
  }
}

private final class TemporaryDirectory {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuotaBarTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}
