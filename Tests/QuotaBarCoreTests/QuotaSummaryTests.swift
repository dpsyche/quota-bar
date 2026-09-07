import Testing

@testable import QuotaBarCore

struct QuotaSummaryTests {
  @Test
  func thresholdBoundariesAreInclusiveAtFiftyAndTwenty() {
    #expect(QuotaSignal.forRemaining(50) == .healthy)
    #expect(QuotaSignal.forRemaining(49.999) == .caution)
    #expect(QuotaSignal.forRemaining(20) == .caution)
    #expect(QuotaSignal.forRemaining(19.999) == .critical)
    #expect(QuotaSignal.forRemaining(0) == .critical)
    #expect(QuotaSignal.forRemaining(nil) == .neutral)
    #expect(QuotaSignal.forRemaining(.nan) == .neutral)
    #expect(QuotaSignal.forRemaining(.infinity) == .neutral)
  }

  @Test
  func tightestSelectionIgnoresUnknownAvailabilityRatherThanTreatingItAsZero() throws {
    let unknown = provider(
      id: "cursor",
      effective: [EffectiveAvailability(scope: "unresolved", status: .unknown)],
      windows: [QuotaWindow(id: "raw", label: "raw", kind: .monthly, percentRemaining: 0)]
    )
    let healthy = provider(id: "codex", remaining: 72)
    let caution = provider(id: "claude", remaining: 34)
    let report = QuotaAxiResponse(
      generatedAt: "2026-01-01T00:00:00Z",
      providers: [unknown, healthy, caution]
    )

    let tightest = try #require(QuotaSummary.tightestKnown(in: report))
    #expect(tightest.providerID == "claude")
    #expect(tightest.availability.effectivePercentRemaining == 34)
  }

  @Test
  func noKnownEffectiveQuotaProducesNeutralHeadline() {
    let unknown = provider(
      id: "cursor",
      effective: [EffectiveAvailability(scope: "unresolved", status: .unknown)]
    )
    let report = QuotaAxiResponse(
      generatedAt: "2026-01-01T00:00:00Z",
      providers: [unknown]
    )

    let percentage = QuotaSummary.tightestKnown(in: report)?.availability.effectivePercentRemaining
    #expect(percentage == nil)
    #expect(QuotaSignal.forRemaining(percentage) == .neutral)
  }

  @Test
  func staleProviderIsExcludedEvenIfItHasALowHistoricalValue() throws {
    let stale = provider(id: "old", remaining: 5, status: .stale, stale: true)
    let current = provider(id: "current", remaining: 81)
    let report = QuotaAxiResponse(
      generatedAt: "2026-01-01T00:00:00Z",
      providers: [stale, current]
    )

    let tightest = try #require(QuotaSummary.tightestKnown(in: report))
    #expect(tightest.providerID == "current")
    #expect(tightest.availability.effectivePercentRemaining == 81)
  }

  @Test
  func staleProviderRetainsKnownEffectiveQuotaForCardDisplay() throws {
    let stale = provider(id: "old", remaining: 5, status: .stale, stale: true)

    #expect(QuotaSummary.tightestKnown(for: stale) == nil)
    let displayed = try #require(QuotaSummary.knownForDisplay(for: stale))
    #expect(displayed.availability.effectivePercentRemaining == 5)
  }

  private func provider(
    id: String,
    remaining: Double,
    status: ProviderStatus = .fresh,
    stale: Bool = false
  ) -> ProviderQuota {
    provider(
      id: id,
      effective: [
        EffectiveAvailability(
          scope: "all_models",
          status: .known,
          effectivePercentRemaining: remaining,
          boundedBy: ["weekly"],
          limitingWindowIds: ["weekly"]
        )
      ],
      status: status,
      stale: stale
    )
  }

  private func provider(
    id: String,
    effective: [EffectiveAvailability],
    windows: [QuotaWindow] = [],
    status: ProviderStatus = .fresh,
    stale: Bool = false
  ) -> ProviderQuota {
    ProviderQuota(
      provider: id,
      label: id.capitalized,
      source: .api,
      windows: windows,
      quotaSemantics: QuotaSemantics(
        status: effective.allSatisfy { $0.status == .known } ? .known : .unknown,
        description: "Synthetic relationship",
        effectiveAvailability: effective
      ),
      state: ProviderState(status: status, stale: stale, sourcesTried: ["test"])
    )
  }
}
