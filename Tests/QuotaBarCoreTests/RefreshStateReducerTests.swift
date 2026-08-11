import Foundation
import Testing

@testable import QuotaBarCore

struct RefreshStateReducerTests {
  @Test
  func transientFailurePreservesLastSuccessfulSnapshotAndMarksItStale() throws {
    let report = sampleReport(remaining: 63)
    let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let fresh = RefreshStateReducer.success(report: report, at: savedAt)

    let failed = RefreshStateReducer.failure(
      previous: fresh,
      message: "Collector timed out."
    )

    #expect(failed.report?.generatedAt == report.generatedAt)
    let preserved = try #require(failed.report)
    #expect(QuotaSummary.tightestKnown(in: preserved)?.availability.effectivePercentRemaining == 63)
    #expect(failed.lastSuccessfulRefresh == savedAt)
    #expect(failed.isStale)
    #expect(failed.failureMessage == "Collector timed out.")
  }

  @Test
  func cachedSnapshotStartsStaleUntilRefreshSucceeds() {
    let report = sampleReport(remaining: 50)
    let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

    let initial = RefreshStateReducer.initial(
      cachedSnapshot: StoredSnapshot(savedAt: savedAt, report: report)
    )

    #expect(initial.report != nil)
    #expect(initial.lastSuccessfulRefresh == savedAt)
    #expect(initial.isStale)
  }

  @Test
  func failureWithoutSnapshotDoesNotInventStaleQuota() {
    let initial = RefreshStateReducer.initial(cachedSnapshot: nil)
    let failed = RefreshStateReducer.failure(previous: initial, message: "Not found")

    #expect(failed.report == nil)
    #expect(failed.lastSuccessfulRefresh == nil)
    #expect(!failed.isStale)
    #expect(failed.failureMessage == "Not found")
  }

  private func sampleReport(remaining: Double) -> QuotaAxiResponse {
    QuotaAxiResponse(
      generatedAt: "2026-01-01T00:00:00Z",
      providers: [
        ProviderQuota(
          provider: "codex",
          label: "Codex",
          source: .api,
          windows: [],
          quotaSemantics: QuotaSemantics(
            status: .known,
            description: "Synthetic relationship",
            effectiveAvailability: [
              EffectiveAvailability(
                scope: "all_models",
                status: .known,
                effectivePercentRemaining: remaining
              )
            ]
          ),
          state: ProviderState(status: .fresh, stale: false, sourcesTried: ["test"])
        )
      ]
    )
  }
}
