import Foundation

public enum QuotaSchemaError: Error, Equatable, Sendable {
  case unsupportedVersion(Int)
}

public struct QuotaAxiResponse: Codable, Sendable {
  public static let supportedSchemaVersions = [3, 5]

  public let generatedAt: String
  public let schemaVersion: Int
  public let providers: [ProviderQuota]
  public let help: [String]?

  public init(
    generatedAt: String,
    schemaVersion: Int = 3,
    providers: [ProviderQuota],
    help: [String]? = nil
  ) {
    self.generatedAt = generatedAt
    self.schemaVersion = schemaVersion
    self.providers = providers
    self.help = help
  }

  private enum CodingKeys: String, CodingKey {
    case generatedAt, schemaVersion, providers, help
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    // Check the envelope before touching a potentially incompatible provider body.
    guard Self.supportedSchemaVersions.contains(schemaVersion) else {
      throw QuotaSchemaError.unsupportedVersion(schemaVersion)
    }
    generatedAt = try container.decode(String.self, forKey: .generatedAt)
    providers = try container.decode([ProviderQuota].self, forKey: .providers)
    help = try container.decodeIfPresent([String].self, forKey: .help)
  }
}

public enum ProviderSource: String, Codable, Sendable {
  case oauth
  case cliRPC = "cli-rpc"
  case cli
  case piOpenAICodex = "pi:openai-codex"
  case api
  case web
  case cache
  case unavailable
  case unknown

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    // Provenance is display metadata, never quota or sign-in evidence.
    self = Self(rawValue: value) ?? .unknown
  }
}

public enum ProviderStatus: String, Codable, Sendable {
  case fresh
  case stale
  case unavailable
  case authRequired = "auth_required"
  case rateLimited = "rate_limited"
  case error
}

public enum ProviderAuthStatus: String, Codable, Sendable {
  case usable
  case expiredRefreshable = "expired_refreshable"
  case unusable
}

public enum ProviderStateReason: String, Codable, Sendable {
  case keychainAccessRequired = "keychain_access_required"
  case credentialsExpired = "credentials_expired"
}

public struct ProviderState: Codable, Sendable {
  public let status: ProviderStatus
  public let stale: Bool
  public let refreshedAt: String?
  public let error: String?
  public let retryAfter: String?
  public let authStatus: ProviderAuthStatus?
  public let reason: ProviderStateReason?
  public let remedyCommand: String?
  public let untrustedWindowIds: [String]?
  public let sourcesTried: [String]?

  public init(
    status: ProviderStatus,
    stale: Bool,
    refreshedAt: String? = nil,
    error: String? = nil,
    retryAfter: String? = nil,
    authStatus: ProviderAuthStatus? = nil,
    reason: ProviderStateReason? = nil,
    remedyCommand: String? = nil,
    untrustedWindowIds: [String]? = nil,
    sourcesTried: [String]? = nil
  ) {
    self.status = status
    self.stale = stale
    self.refreshedAt = refreshedAt
    self.error = error
    self.retryAfter = retryAfter
    self.authStatus = authStatus
    self.reason = reason
    self.remedyCommand = remedyCommand
    self.untrustedWindowIds = untrustedWindowIds
    self.sourcesTried = sourcesTried
  }

  public var isCurrent: Bool {
    status == .fresh && !stale
  }
}

public enum QuotaWindowKind: String, Codable, Sendable {
  case session
  case weekly
  case monthly
  case model
  case credits
  case unknown
}

public enum QuotaPaceStatus: String, Codable, Sendable {
  case ahead
  case onPace = "on_pace"
  case behind
  case unknown
}

public enum QuotaPaceReason: String, Codable, Sendable {
  case stale
  case missingUsage = "missing_usage"
  case missingCycle = "missing_cycle"
  case invalidCycle = "invalid_cycle"
  case futureCycleStart = "future_cycle_start"
  case expiredReset = "expired_reset"
  case unsupportedPeriod = "unsupported_period"
}

public enum ProjectionConfidence: String, Codable, Sendable {
  case early
  case established
}

public enum ProjectionBasis: String, Codable, Sendable {
  case cycleAverage = "cycle_average"
}

public enum PaceCycleBasis: String, Codable, Sendable {
  case startsAtResetsAt = "starts_at_resets_at"
  case windowSeconds = "window_seconds"
}

public struct QuotaPace: Codable, Sendable {
  public let status: QuotaPaceStatus
  public let reason: QuotaPaceReason?
  public let timeRemainingPercent: Double?
  public let elapsedPercent: Double?
  public let reservePercentPoints: Double?
  public let burnMultiple: Double?
  public let projectedExhaustedAt: String?
  public let projectionConfidence: ProjectionConfidence?
  public let projectionBasis: ProjectionBasis?
  public let cycleBasis: PaceCycleBasis?
  public let cycleSeconds: Double?

  public init(
    status: QuotaPaceStatus,
    reason: QuotaPaceReason? = nil,
    timeRemainingPercent: Double? = nil,
    elapsedPercent: Double? = nil,
    reservePercentPoints: Double? = nil,
    burnMultiple: Double? = nil,
    projectedExhaustedAt: String? = nil,
    projectionConfidence: ProjectionConfidence? = nil,
    projectionBasis: ProjectionBasis? = nil,
    cycleBasis: PaceCycleBasis? = nil,
    cycleSeconds: Double? = nil
  ) {
    self.status = status
    self.reason = reason
    self.timeRemainingPercent = timeRemainingPercent
    self.elapsedPercent = elapsedPercent
    self.reservePercentPoints = reservePercentPoints
    self.burnMultiple = burnMultiple
    self.projectedExhaustedAt = projectedExhaustedAt
    self.projectionConfidence = projectionConfidence
    self.projectionBasis = projectionBasis
    self.cycleBasis = cycleBasis
    self.cycleSeconds = cycleSeconds
  }
}

public struct QuotaWindow: Codable, Sendable {
  public let id: String
  public let label: String
  public let kind: QuotaWindowKind
  public let percentUsed: Double?
  public let percentRemaining: Double?
  public let startsAt: String?
  public let resetsAt: String?
  public let resetText: String?
  public let windowSeconds: Double?
  public let spentUsd: Double?
  public let limitUsd: Double?
  public let pace: QuotaPace?

  public init(
    id: String,
    label: String,
    kind: QuotaWindowKind,
    percentUsed: Double? = nil,
    percentRemaining: Double? = nil,
    startsAt: String? = nil,
    resetsAt: String? = nil,
    resetText: String? = nil,
    windowSeconds: Double? = nil,
    spentUsd: Double? = nil,
    limitUsd: Double? = nil,
    pace: QuotaPace? = nil
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.percentUsed = percentUsed
    self.percentRemaining = percentRemaining
    self.startsAt = startsAt
    self.resetsAt = resetsAt
    self.resetText = resetText
    self.windowSeconds = windowSeconds
    self.spentUsd = spentUsd
    self.limitUsd = limitUsd
    self.pace = pace
  }
}

public enum EffectiveAvailabilityStatus: String, Codable, Sendable {
  case known
  case unknown
}

public enum EffectivePaceStatus: String, Codable, Sendable {
  case ahead
  case onPace = "on_pace"
  case behind
  case mixed
  case unknown
}

public struct EffectivePace: Codable, Sendable {
  public let status: EffectivePaceStatus
  public let aheadWindowIds: [String]?
  public let behindWindowIds: [String]?
  public let onPaceWindowIds: [String]?
  public let unknownWindowIds: [String]?
  public let worstReservePercentPoints: Double?
  public let worstReserveWindowId: String?

  public init(
    status: EffectivePaceStatus,
    aheadWindowIds: [String]? = nil,
    behindWindowIds: [String]? = nil,
    onPaceWindowIds: [String]? = nil,
    unknownWindowIds: [String]? = nil,
    worstReservePercentPoints: Double? = nil,
    worstReserveWindowId: String? = nil
  ) {
    self.status = status
    self.aheadWindowIds = aheadWindowIds
    self.behindWindowIds = behindWindowIds
    self.onPaceWindowIds = onPaceWindowIds
    self.unknownWindowIds = unknownWindowIds
    self.worstReservePercentPoints = worstReservePercentPoints
    self.worstReserveWindowId = worstReserveWindowId
  }
}

public enum EffectiveRunwayStatus: String, Codable, Sendable {
  case exhaustedNow = "exhausted_now"
  case projectedExhaustion = "projected_exhaustion"
  case throughReset = "through_reset"
  case unknown
}

public struct EffectiveRunway: Codable, Sendable {
  public let status: EffectiveRunwayStatus
  public let usableRunwaySeconds: Double?
  public let projectedExhaustedAt: String?
  public let limitingWindowId: String?
  public let projectionConfidence: ProjectionConfidence?
  public let projectionBasis: ProjectionBasis?
  public let unmeasurableWindowIds: [String]?

  public init(
    status: EffectiveRunwayStatus,
    usableRunwaySeconds: Double? = nil,
    projectedExhaustedAt: String? = nil,
    limitingWindowId: String? = nil,
    projectionConfidence: ProjectionConfidence? = nil,
    projectionBasis: ProjectionBasis? = nil,
    unmeasurableWindowIds: [String]? = nil
  ) {
    self.status = status
    self.usableRunwaySeconds = usableRunwaySeconds
    self.projectedExhaustedAt = projectedExhaustedAt
    self.limitingWindowId = limitingWindowId
    self.projectionConfidence = projectionConfidence
    self.projectionBasis = projectionBasis
    self.unmeasurableWindowIds = unmeasurableWindowIds
  }
}

public struct EffectiveAvailability: Codable, Sendable {
  public let scope: String
  public let status: EffectiveAvailabilityStatus
  public let effectivePercentRemaining: Double?
  public let boundedBy: [String]
  public let limitingWindowIds: [String]?
  public let pace: EffectivePace?
  public let runway: EffectiveRunway?

  public init(
    scope: String,
    status: EffectiveAvailabilityStatus,
    effectivePercentRemaining: Double? = nil,
    boundedBy: [String] = [],
    limitingWindowIds: [String]? = nil,
    pace: EffectivePace? = nil,
    runway: EffectiveRunway? = nil
  ) {
    self.scope = scope
    self.status = status
    self.effectivePercentRemaining = effectivePercentRemaining
    self.boundedBy = boundedBy
    self.limitingWindowIds = limitingWindowIds
    self.pace = pace
    self.runway = runway
  }
}

public enum QuotaSemanticsStatus: String, Codable, Sendable {
  case known
  case partial
  case unknown
}

public struct QuotaSemantics: Codable, Sendable {
  public let status: QuotaSemanticsStatus
  public let description: String?
  public let effectiveAvailability: [EffectiveAvailability]
  public let unresolvedWindowIds: [String]?

  public init(
    status: QuotaSemanticsStatus,
    description: String? = nil,
    effectiveAvailability: [EffectiveAvailability],
    unresolvedWindowIds: [String]? = nil
  ) {
    self.status = status
    self.description = description
    self.effectiveAvailability = effectiveAvailability
    self.unresolvedWindowIds = unresolvedWindowIds
  }
}

public struct ProviderCredits: Codable, Sendable {
  public enum Unit: String, Codable, Sendable {
    case usd
    case credits
  }

  public let remaining: Double?
  public let unlimited: Bool?
  public let unit: Unit?

  public init(remaining: Double? = nil, unlimited: Bool? = nil, unit: Unit? = nil) {
    self.remaining = remaining
    self.unlimited = unlimited
    self.unit = unit
  }
}

public struct ProviderQuota: Codable, Sendable {
  public let provider: String
  public let label: String?
  public let source: ProviderSource?
  public let plan: String?
  public let windows: [QuotaWindow]
  public let quotaSemantics: QuotaSemantics?
  public let credits: ProviderCredits?
  public let state: ProviderState

  public init(
    provider: String,
    label: String? = nil,
    source: ProviderSource? = nil,
    plan: String? = nil,
    windows: [QuotaWindow],
    quotaSemantics: QuotaSemantics? = nil,
    credits: ProviderCredits? = nil,
    state: ProviderState
  ) {
    self.provider = provider
    self.label = label
    self.source = source
    self.plan = plan
    self.windows = windows
    self.quotaSemantics = quotaSemantics
    self.credits = credits
    self.state = state
  }
}
