import Foundation
import Testing

@testable import QuotaBarCore

struct QuotaSchemaDecodingTests {
  @Test
  func decodesLegacyQuotaAxiSchemaIncludingSemanticsPaceAndRunway() throws {
    let fixture = try #require(Bundle.module.url(forResource: "quota-v3", withExtension: "json"))
    let report = try JSONDecoder().decode(QuotaAxiResponse.self, from: Data(contentsOf: fixture))

    #expect(report.schemaVersion == 3)
    #expect(report.generatedAt == "2026-01-15T12:00:00.000Z")
    #expect(report.providers.count == 3)

    let codex = try #require(report.providers.first { $0.provider == "codex" })
    #expect(codex.source == .cliRPC)
    #expect(codex.plan == "plus")
    #expect(codex.state.status == .fresh)
    #expect(codex.state.authStatus == .usable)
    #expect(codex.credits?.remaining == 12.5)
    #expect(codex.credits?.unit == .usd)

    let weekly = try #require(codex.windows.first { $0.id == "weekly" })
    #expect(weekly.kind == .weekly)
    #expect(weekly.percentRemaining == 47)
    #expect(weekly.pace?.status == .ahead)
    #expect(weekly.pace?.reservePercentPoints == -15)
    #expect(weekly.pace?.cycleBasis == .windowSeconds)

    let effective = try #require(codex.quotaSemantics?.effectiveAvailability.first)
    #expect(effective.status == .known)
    #expect(effective.effectivePercentRemaining == 47)
    #expect(effective.limitingWindowIds == ["weekly"])
    #expect(effective.pace?.status == .mixed)
    #expect(effective.pace?.worstReserveWindowId == "weekly")
    #expect(effective.runway?.status == .projectedExhaustion)
    #expect(effective.runway?.usableRunwaySeconds == 165_600)
    #expect(effective.runway?.projectionBasis == .cycleAverage)

    let cursor = try #require(report.providers.first { $0.provider == "cursor" })
    #expect(cursor.quotaSemantics?.status == .unknown)
    #expect(cursor.quotaSemantics?.unresolvedWindowIds == ["included_usage", "api_usage"])
    #expect(cursor.quotaSemantics?.effectiveAvailability.first?.effectivePercentRemaining == nil)
    #expect(cursor.windows.first?.pace?.reason == .unsupportedPeriod)

    let claude = try #require(report.providers.first { $0.provider == "claude" })
    #expect(claude.state.status == .authRequired)
    #expect(claude.state.authStatus == .unusable)
    #expect(claude.windows.isEmpty)
  }

  @Test
  func decodesDefaultV5WithoutInventingDemotedMetadataOrUnknownQuota() throws {
    let fixture = try #require(Bundle.module.url(forResource: "quota-v5", withExtension: "json"))
    let report = try JSONDecoder().decode(QuotaAxiResponse.self, from: Data(contentsOf: fixture))
    #expect(report.schemaVersion == 5)
    #expect(report.providers.allSatisfy { $0.label == nil && $0.source == nil })
    #expect(report.providers.allSatisfy { $0.state.sourcesTried == nil })
    #expect(report.providers.allSatisfy { $0.state.refreshedAt == nil })
    #expect(report.providers.allSatisfy { $0.quotaSemantics?.description == nil })

    let codex = try #require(report.providers.first { $0.provider == "codex" })
    #expect(codex.displayLabel == "Codex")
    #expect(codex.sourceLabel == nil)
    #expect(codex.state.authStatus == .usable)
    let window = try #require(codex.windows.first)
    #expect(window.percentRemaining == 47)
    #expect(window.percentUsed == nil)
    #expect(window.windowSeconds == nil)
    #expect(window.pace?.reservePercentPoints == -15)
    #expect(window.pace?.burnMultiple == 1.39)
    #expect(window.pace?.timeRemainingPercent == nil)
    #expect(window.pace?.projectionConfidence == nil)
    let availability = try #require(codex.quotaSemantics?.effectiveAvailability.first)
    #expect(availability.pace?.onPaceWindowIds == nil)
    #expect(availability.pace?.behindWindowIds == nil)
    #expect(availability.runway?.status == .projectedExhaustion)
    #expect(availability.runway?.usableRunwaySeconds == 165_600)
    #expect(availability.runway?.projectionConfidence == .established)
    #expect(availability.runway?.projectionBasis == nil)

    let unresolved = try #require(report.providers.first { $0.provider == "cursor" })
    #expect(QuotaSummary.knownForDisplay(for: unresolved) == nil)
    #expect(unresolved.windows.last?.percentRemaining == nil)
    #expect(unresolved.quotaSemantics?.effectiveAvailability.first?.effectivePercentRemaining == nil)
    let stale = try #require(report.providers.first { $0.provider == "kimi" })
    #expect(QuotaSummary.tightestKnown(for: stale) == nil)
    #expect(QuotaSummary.knownForDisplay(for: stale)?.availability.effectivePercentRemaining == 3)
    let tightest = try #require(QuotaSummary.tightestKnown(in: report))
    #expect(tightest.providerID == "codex")
    #expect(QuotaSignal.forRemaining(tightest.availability.effectivePercentRemaining) == .caution)
  }

  @Test(arguments: [4, 6, 99])
  func unsupportedVersionIsDiagnosedBeforeIncompatibleBody(version: Int) throws {
    let data = Data("{\"schemaVersion\":\(version),\"providers\":\"different shape\"}".utf8)
    do {
      _ = try JSONDecoder().decode(QuotaAxiResponse.self, from: data)
      Issue.record("Expected unsupported schema before body decoding")
    } catch {
      #expect(error as? QuotaSchemaError == .unsupportedVersion(version))
    }
  }

  @Test(arguments: ["cli", "pi:openai-codex", "synthetic-future-source"])
  func provenanceCanBeNewOrUnknownWithoutBecomingAuthEvidence(source: String) throws {
    let data = Data("""
      {"generatedAt":"synthetic","schemaVersion":5,"providers":[{
        "provider":"synthetic-provider","source":"\(source)","windows":[],
        "state":{"status":"unavailable","stale":false}
      }]}
      """.utf8)
    let report = try JSONDecoder().decode(QuotaAxiResponse.self, from: data)
    let provider = try #require(report.providers.first)
    #expect(provider.displayLabel == "synthetic-provider")
    #expect(provider.state.authStatus == nil)
    #expect(QuotaSummary.tightestKnown(in: report) == nil)
    switch source {
    case "cli":
      #expect(provider.source == .cli)
      #expect(provider.sourceLabel == "CLI")
    case "pi:openai-codex":
      #expect(provider.source == .piOpenAICodex)
      #expect(provider.sourceLabel == "Pi")
    default:
      #expect(provider.source == .unknown)
      #expect(provider.sourceLabel == nil)
    }
  }

  @Test
  func newSourceToleranceDoesNotRelaxQuotaOrAuthStateValidation() throws {
    let data = Data("""
      {"generatedAt":"synthetic","schemaVersion":5,"providers":[{
        "provider":"synthetic","source":"new-source","windows":[],
        "state":{"status":"new-status","stale":false}
      }]}
      """.utf8)
    do {
      _ = try JSONDecoder().decode(QuotaAxiResponse.self, from: data)
      Issue.record("Unknown safety-relevant states must not become fresh or known")
    } catch {
      #expect(error is DecodingError)
    }
  }
}
