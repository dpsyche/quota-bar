import Foundation
import Testing

@testable import QuotaBarCore

struct ProviderPresentationTests {
  @Test
  func orderSurvivesFilteringMissingResultsRefreshAndNewIdentities() throws {
    let preferences = try PresentationPreferences()
    defer { preferences.remove() }
    var state = ProviderPresentation(defaults: preferences.defaults)
    state.reconcile([provider("a"), provider("b"), provider("c")])
    let movedFirst = state.move("c", to: "a", visibleIDs: ["a", "b", "c"])
    #expect(movedFirst)
    #expect(state.order == ["c", "a", "b"])
    state.reconcile([provider("b", status: .authRequired), provider("a"), provider("d")])
    #expect(
      state.visibleProviders(in: [
        provider("d"), provider("b", status: .authRequired), provider("a"),
      ]).map(\.provider) == ["a", "d"])
    #expect(state.order == ["c", "a", "b", "d"])
    let movedHidden = state.move("b", to: "a", visibleIDs: ["a", "d"])
    let movedNew = state.move("d", to: "a", visibleIDs: ["a", "d"])
    #expect(!movedHidden)
    #expect(movedNew)
    state.reconcile([provider("a"), provider("b"), provider("c"), provider("d"), provider("d")])
    let reopened = ProviderPresentation(defaults: preferences.reopen())
    #expect(reopened.order == ["c", "d", "a", "b"])
    #expect(
      reopened.visibleProviders(in: [
        provider("b"), provider("a"), provider("d"), provider("c"), provider("d"),
      ]).map(\.provider) == ["c", "d", "a", "b"])
  }

  @Test
  func invalidAndDuplicateIdentitiesCannotCorruptPersistedOrder() throws {
    let preferences = try PresentationPreferences()
    defer { preferences.remove() }
    preferences.defaults.set(["a", "a", "", "hidden", "b"], forKey: ProviderPresentation.orderKey)
    var state = ProviderPresentation(defaults: preferences.defaults)
    let providers = [provider("b"), provider("a"), provider("c"), provider("c"), provider("")]
    state.reconcile(providers)
    #expect(state.order == ["a", "hidden", "b", "c"])
    #expect(state.visibleProviders(in: providers).map(\.provider) == ["a", "b", "c"])
    let movedExternal = state.move("external", to: "a", visibleIDs: ["external", "a"])
    let movedSelf = state.move("a", to: "a", visibleIDs: ["a"])
    #expect(!movedExternal)
    #expect(!movedSelf)
    #expect(ProviderPresentation(defaults: preferences.reopen()).order == state.order)
  }

  @Test
  func structuredSignInDoesNotDependOnQuotaWindowsLabelsOrErrorProse() throws {
    let preferences = try PresentationPreferences()
    defer { preferences.remove() }
    var state = ProviderPresentation(defaults: preferences.defaults)
    let providers = [
      provider("usable", status: .unavailable, auth: .usable),
      provider("refreshable", status: .unavailable, auth: .expiredRefreshable),
      provider("success"),
      provider("cached", status: .stale),
      provider("missing", status: .authRequired),
      provider("denied", status: .authRequired, auth: .usable),
      provider("keychain", status: .stale, auth: .usable, reason: .keychainAccessRequired),
      provider("unknown", status: .unavailable),
      provider("failed", status: .error, auth: .unusable),
    ]
    state.reconcile(providers)
    #expect(
      state.visibleProviders(in: providers).map(\.provider) == [
        "usable", "refreshable", "success",
      ])
    #expect(providers.allSatisfy { $0.windows.isEmpty })
    #expect(
      QuotaSummary.tightestKnown(
        in: QuotaAxiResponse(generatedAt: "synthetic", providers: providers)) == nil)
  }

  @Test
  func transientAuthResolutionFailureRetainsOnlyKnownSignInAcrossRelaunch() throws {
    let preferences = try PresentationPreferences()
    defer { preferences.remove() }
    var state = ProviderPresentation(defaults: preferences.defaults)
    state.reconcile([provider("known")])
    let failure = provider("known", status: .error, auth: .unusable)
    state.reconcile([failure, provider("unknown", status: .error)])
    #expect(state.isVisible(failure))
    #expect(state.signInIsUncertain(failure))
    var reopened = ProviderPresentation(defaults: preferences.reopen())
    #expect(reopened.isVisible(failure))
    reopened.reconcile([provider("known", status: .authRequired)])
    reopened.reconcile([failure])
    #expect(!reopened.isVisible(failure))
    #expect(reopened.order == ["known", "unknown"])
  }

  @Test(
    arguments: [ProviderStatus.error, .stale, .unavailable, .rateLimited],
    [ProviderAuthStatus?.none, .unusable])
  func ambiguousAuthNeedsPriorEvidenceAndNeverErasesIt(
    status: ProviderStatus,
    auth: ProviderAuthStatus?
  ) throws {
    let preferences = try PresentationPreferences()
    defer { preferences.remove() }
    var state = ProviderPresentation(defaults: preferences.defaults)
    state.reconcile([provider("known")])
    let known = provider("known", status: status, auth: auth)
    let neverConfirmed = provider("new", status: status, auth: auth)
    state.reconcile([known, neverConfirmed])
    #expect(state.visibleProviders(in: [known, neverConfirmed]).map(\.provider) == ["known"])
    #expect(state.signInIsUncertain(known))
    #expect(!state.signInIsUncertain(neverConfirmed))
    let relaunched = ProviderPresentation(defaults: preferences.reopen())
    #expect(relaunched.isVisible(known))
    #expect(!relaunched.isVisible(neverConfirmed))
    // Confirmed auth-required overrides even local usable/refreshable evidence.
    state.reconcile([provider("known", status: .authRequired, auth: .expiredRefreshable)])
    #expect(!state.isVisible(known))
    #expect(state.order == ["known", "new"])
  }

  @Test
  func omittedDisplayMetadataDoesNotChangeSignInEvidenceOrStableIdentity() throws {
    let preferences = try PresentationPreferences()
    defer { preferences.remove() }
    var state = ProviderPresentation(defaults: preferences.defaults)
    let confirmed = ProviderQuota(
      provider: "codex", windows: [],
      state: ProviderState(status: .unavailable, stale: false, authStatus: .usable))
    let unknown = ProviderQuota(
      provider: "new-provider", source: .unknown, windows: [],
      state: ProviderState(status: .unavailable, stale: false))
    let denied = ProviderQuota(
      provider: "claude", windows: [],
      state: ProviderState(status: .authRequired, stale: false, authStatus: .usable))
    state.reconcile([confirmed, unknown, denied])
    #expect(state.visibleProviders(in: [confirmed, unknown, denied]).map(\.provider) == ["codex"])
    #expect(state.order == ["codex", "new-provider", "claude"])
    #expect(confirmed.displayLabel == "Codex")
    #expect(confirmed.sourceLabel == nil)
    #expect(unknown.displayLabel == "new-provider")
    #expect(unknown.sourceLabel == nil)
    #expect(denied.displayLabel == "Claude")
    let custom = ProviderQuota(
      provider: "codex", label: "Reported label", source: .api, windows: [],
      state: ProviderState(status: .fresh, stale: false))
    #expect(custom.displayLabel == "Reported label")
    #expect(custom.sourceLabel == "API")
  }

  private func provider(
    _ id: String, status: ProviderStatus = .fresh,
    auth: ProviderAuthStatus? = nil, reason: ProviderStateReason? = nil
  ) -> ProviderQuota {
    ProviderQuota(
      provider: id, label: "Same display label", source: .api, windows: [],
      state: ProviderState(
        status: status, stale: status == .stale,
        error: "Sign-in required (untrusted prose)",
        authStatus: auth, reason: reason))
  }
}

private struct PresentationPreferences {
  let name = "local.QuotaBar.PresentationTests." + UUID().uuidString
  let defaults: UserDefaults
  init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
  func reopen() -> UserDefaults { UserDefaults(suiteName: name)! }
  func remove() { defaults.removePersistentDomain(forName: name) }
}
