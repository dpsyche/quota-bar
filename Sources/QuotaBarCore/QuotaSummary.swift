import Foundation

public enum QuotaSignal: String, Equatable, Sendable {
  case healthy
  case caution
  case critical
  case neutral

  public static func forRemaining(_ percentage: Double?) -> QuotaSignal {
    guard let percentage, percentage.isFinite else { return .neutral }
    if percentage >= 50 { return .healthy }
    if percentage >= 20 { return .caution }
    return .critical
  }
}

public struct KnownQuota: Equatable, Sendable {
  public let providerID: String
  public let providerLabel: String
  public let availability: EffectiveAvailability

  public init(providerID: String, providerLabel: String, availability: EffectiveAvailability) {
    self.providerID = providerID
    self.providerLabel = providerLabel
    self.availability = availability
  }

  public static func == (lhs: KnownQuota, rhs: KnownQuota) -> Bool {
    lhs.providerID == rhs.providerID && lhs.providerLabel == rhs.providerLabel
      && lhs.availability.scope == rhs.availability.scope
      && lhs.availability.effectivePercentRemaining == rhs.availability.effectivePercentRemaining
  }
}

public enum QuotaSummary {
  public static func tightestKnown(in report: QuotaAxiResponse) -> KnownQuota? {
    report.providers
      .compactMap(tightestKnown(for:))
      .min { lhs, rhs in
        guard
          let left = lhs.availability.effectivePercentRemaining,
          let right = rhs.availability.effectivePercentRemaining
        else { return false }
        return left < right
      }
  }

  public static func tightestKnown(for provider: ProviderQuota) -> KnownQuota? {
    guard provider.state.isCurrent else { return nil }

    let availability = provider.quotaSemantics?.effectiveAvailability
      .filter(isUsableKnownAvailability)
      .min { left, right in
        guard
          let leftValue = left.effectivePercentRemaining,
          let rightValue = right.effectivePercentRemaining
        else { return false }
        return leftValue < rightValue
      }

    guard let availability else { return nil }
    return KnownQuota(
      providerID: provider.provider,
      providerLabel: provider.label,
      availability: availability
    )
  }

  private static func isUsableKnownAvailability(_ availability: EffectiveAvailability) -> Bool {
    guard
      availability.status == .known,
      let value = availability.effectivePercentRemaining
    else { return false }
    return value.isFinite && (0...100).contains(value)
  }
}
