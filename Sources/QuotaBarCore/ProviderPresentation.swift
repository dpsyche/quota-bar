import Foundation

/// Presentation only: never feeds the quota summary or ring policy.
public struct ProviderPresentation {
  public static let orderKey = "ProviderTileOrder.v1"
  public static let signedInKey = "PreviouslySignedInProviders.v1"
  public static let emptyMessage =
    "No signed-in providers are available. Sign in through your provider's existing app or CLI, then click Refresh."

  public private(set) var order: [String]
  private var previouslySignedIn: Set<String>
  private let defaults: UserDefaults

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    order = Self.unique(defaults.stringArray(forKey: Self.orderKey) ?? [])
    previouslySignedIn = Set(defaults.stringArray(forKey: Self.signedInKey) ?? [])
  }

  public mutating func reconcile(_ providers: [ProviderQuota]) {
    // Never remove absent/filtered identities. Append newcomers in collector order.
    order = Self.unique(order + providers.map(\.provider))
    for provider in providers where !provider.provider.isEmpty {
      switch Self.evidence(provider.state) {
      case .signedIn: previouslySignedIn.insert(provider.provider)
      case .signedOut: previouslySignedIn.remove(provider.provider)
      case .unknown: break
      }
    }
    save()
  }

  public func visibleProviders(in providers: [ProviderQuota]) -> [ProviderQuota] {
    var seen = Set<String>()
    let visible = providers.filter {
      !$0.provider.isEmpty && seen.insert($0.provider).inserted && isVisible($0)
    }
    let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    return visible.enumerated().sorted {
      let left = positions[$0.element.provider] ?? (order.count + $0.offset)
      let right = positions[$1.element.provider] ?? (order.count + $1.offset)
      return left < right
    }.map(\.element)
  }

  public func isVisible(_ provider: ProviderQuota) -> Bool {
    switch Self.evidence(provider.state) {
    case .signedIn: return true
    case .signedOut: return false
    case .unknown: return previouslySignedIn.contains(provider.provider)
    }
  }

  public func signInIsUncertain(_ provider: ProviderQuota) -> Bool {
    Self.evidence(provider.state) == .unknown && previouslySignedIn.contains(provider.provider)
  }

  /// Moves to the target's position (before when moving up, after when moving down).
  /// Only visible identities can participate; hidden slots keep their relative order.
  @discardableResult
  public mutating func move(_ source: String, to target: String, visibleIDs: [String]) -> Bool {
    guard source != target, visibleIDs.contains(source), visibleIDs.contains(target),
      let from = order.firstIndex(of: source), let to = order.firstIndex(of: target)
    else { return false }
    order.remove(at: from)
    order.insert(source, at: to)
    save()
    return true
  }

  private enum Evidence { case signedIn, signedOut, unknown }

  private static func evidence(_ state: ProviderState) -> Evidence {
    // Explicit denial beats cached/local usability. Error prose is never parsed.
    if state.status == .authRequired || state.reason == .keychainAccessRequired {
      return .signedOut
    }
    switch state.authStatus {
    case .usable, .expiredRefreshable: return .signedIn
    case .unusable:
      // Unusable alone means no source established usability, not definitive
      // sign-out. Grok may also wrap credential-resolution failures in stale
      // cache state. Retain only prior positive evidence, explicitly uncertain.
      return .unknown
    case nil:
      // quota-axi successProvider maps a successful authenticated fetch to fresh.
      // Cache freshness alone does not confirm current auth: staleFromCache can
      // wrap auth failures too. A stale report needs explicit or prior evidence.
      if state.status == .fresh && !state.stale { return .signedIn }
      return .unknown
    }
  }

  private mutating func save() {
    defaults.set(order, forKey: Self.orderKey)
    defaults.set(previouslySignedIn.sorted(), forKey: Self.signedInKey)
  }

  private static func unique(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
  }
}
