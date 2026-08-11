import Foundation
import Testing

@testable import QuotaBarCore

struct QuotaSchemaDecodingTests {
  @Test
  func decodesCurrentQuotaAxiSchemaIncludingSemanticsPaceAndRunway() throws {
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
}
