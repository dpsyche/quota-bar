import QuotaBarCore
import SwiftUI

struct QuotaPopoverView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView {
        LazyVStack(spacing: 9) {
          if let message = model.state.failureMessage {
            failureBanner(message)
          }

          if let report = model.state.report {
            ForEach(report.providers, id: \.provider) { provider in
              ProviderCardView(provider: provider, globallyStale: model.state.isStale)
            }
          } else if !model.isRefreshing {
            setupCard
          }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 11)
      }

      footer
    }
    .frame(width: 408, height: 620)
    .background {
      LinearGradient(
        colors: [
          QuotaPalette.background,
          Color(red: 17 / 255, green: 20 / 255, blue: 27 / 255),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
    .foregroundStyle(QuotaPalette.primaryText)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Quota Bar")
          .font(.system(size: 17, weight: .bold, design: .rounded))
        Text(headerSubtitle)
          .font(.system(size: 11.5))
          .foregroundStyle(QuotaPalette.secondaryText)
          .lineLimit(1)
      }

      Spacer()

      Circle()
        .fill(model.headlineSignal.color)
        .frame(width: 8, height: 8)
        .shadow(color: model.headlineSignal.color.opacity(0.28), radius: 5)
        .padding(.top, 7)
        .accessibilityHidden(true)

      Button {
        Task { await model.refresh() }
      } label: {
        if model.isRefreshing {
          ProgressView()
            .controlSize(.small)
            .frame(width: 18, height: 18)
        } else {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 18, height: 18)
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(QuotaPalette.secondaryText)
      .disabled(model.isRefreshing)
      .keyboardShortcut("r", modifiers: .command)
      .help("Refresh quotas (⌘R)")
      .accessibilityLabel(model.isRefreshing ? "Refreshing quotas" : "Refresh quotas")
    }
    .padding(.horizontal, 16)
    .padding(.top, 15)
    .padding(.bottom, 12)
  }

  private var footer: some View {
    HStack(spacing: 10) {
      Text("Tightest known effective quota")
        .lineLimit(1)
      Spacer()
      Menu {
        Button("Choose quota-axi…") {
          model.chooseExecutable()
        }
        if model.configuredPath != nil {
          Button("Use Automatic Discovery") {
            model.clearConfiguredExecutable()
          }
        }
        Divider()
        Button("Quit Quota Bar") {
          model.quit()
        }
        .keyboardShortcut("q", modifiers: .command)
      } label: {
        Image(systemName: "gearshape")
          .frame(width: 18, height: 18)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Quota Bar settings")
      .accessibilityLabel("Quota Bar settings")
    }
    .font(.system(size: 10.5))
    .foregroundStyle(QuotaPalette.secondaryText)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.black.opacity(0.13))
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
  }

  private var setupCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Quota AXI setup", systemImage: "wrench.and.screwdriver")
        .font(.system(size: 14, weight: .semibold))
      Text(
        "Quota Bar could not find quota-axi in your configured location, PATH, common Homebrew or local-bin locations, or NVM installations."
      )
      .font(.system(size: 12))
      .foregroundStyle(QuotaPalette.secondaryText)
      .fixedSize(horizontal: false, vertical: true)
      Button("Choose quota-axi…") {
        model.chooseExecutable()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .modifier(QuotaCardBackground())
  }

  private func failureBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(
        systemName: model.state.isStale ? "clock.badge.exclamationmark" : "exclamationmark.circle"
      )
      .foregroundStyle(QuotaPalette.neutral)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.state.isStale ? "Showing last successful snapshot" : "Refresh unavailable")
          .font(.system(size: 12, weight: .semibold))
        Text(message)
          .font(.system(size: 11))
          .foregroundStyle(QuotaPalette.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(QuotaPalette.neutral.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(QuotaPalette.neutral.opacity(0.22), lineWidth: 1)
    }
  }

  private var headerSubtitle: String {
    if model.isRefreshing { return "All services · refreshing…" }
    if model.state.isStale, let date = model.state.lastSuccessfulRefresh {
      return "All services · stale since \(date.shortAbsoluteDate)"
    }
    if let date = model.state.lastSuccessfulRefresh {
      return "All services · refreshed \(date.relativeDescription)"
    }
    return model.state.failureMessage == nil ? "All services · starting…" : "Setup required"
  }
}

private struct ProviderCardView: View {
  let provider: ProviderQuota
  let globallyStale: Bool

  private var knownQuota: KnownQuota? {
    QuotaSummary.knownForDisplay(for: provider)
  }

  private var percentage: Double? {
    knownQuota?.availability.effectivePercentRemaining
  }

  private var signal: QuotaSignal {
    cardIsStale ? .neutral : QuotaSignal.forRemaining(percentage)
  }

  private var cardIsStale: Bool {
    globallyStale || !provider.state.isCurrent
  }

  private var unresolvedAvailability: EffectiveAvailability? {
    guard unresolvedRelationships else { return nil }
    return provider.quotaSemantics?.effectiveAvailability.first {
      $0.pace != nil || $0.runway != nil
    }
  }

  private var unresolvedRelationships: Bool {
    provider.quotaSemantics?.status != .known
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        providerMark

        VStack(alignment: .leading, spacing: 2) {
          Text(provider.label)
            .font(.system(size: 14, weight: .semibold))
          Text(providerStateText)
            .font(.system(size: 10.5))
            .foregroundStyle(QuotaPalette.secondaryText)
            .lineLimit(2)
        }

        Spacer(minLength: 8)

        VStack(alignment: .trailing, spacing: 1) {
          if let percentage {
            Text("\(percentage.formattedQuotaPercentage)%")
              .font(.system(size: 19, weight: .bold, design: .rounded))
              .monospacedDigit()
            Text(cardIsStale ? "last known" : scopeLabel)
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(QuotaPalette.secondaryText)
          } else {
            Text("—")
              .font(.system(size: 19, weight: .bold, design: .rounded))
              .foregroundStyle(QuotaPalette.neutral)
            Text("combined unknown")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(QuotaPalette.secondaryText)
          }
        }
        .accessibilityElement(children: .combine)
      }

      quotaMeter

      if unresolvedRelationships {
        Label("Combined availability is unknown", systemImage: "questionmark.circle")
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(QuotaPalette.neutral)
          .help(
            provider.quotaSemantics?.description
              ?? "No authoritative window relationship is available.")
      }

      if let availability = knownQuota?.availability {
        effectiveDetails(availability)
      } else if let availability = unresolvedAvailability {
        unresolvedDetails(availability)
      }

      if !provider.windows.isEmpty {
        windowRows
      } else if percentage == nil {
        Text(emptyWindowText)
          .font(.system(size: 10.5))
          .foregroundStyle(QuotaPalette.secondaryText)
      }
    }
    .padding(13)
    .modifier(QuotaCardBackground())
    .accessibilityElement(children: .contain)
  }

  private var providerMark: some View {
    Text(providerInitials)
      .font(.system(size: 10, weight: .bold, design: .rounded))
      .foregroundStyle(QuotaPalette.primaryText)
      .frame(width: 31, height: 31)
      .background(
        Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay(alignment: .bottomTrailing) {
        Circle()
          .fill(signal.color)
          .frame(width: 7, height: 7)
          .overlay(Circle().stroke(QuotaPalette.background, lineWidth: 1.5))
      }
      .accessibilityHidden(true)
  }

  private var quotaMeter: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.09))
        if let percentage {
          Capsule()
            .fill(signal.color)
            .frame(width: geometry.size.width * min(max(percentage, 0), 100) / 100)
        }
      }
    }
    .frame(height: 6)
    .accessibilityElement()
    .accessibilityLabel("Effective remaining quota")
    .accessibilityValue(percentage.map { "\($0.formattedQuotaPercentage) percent" } ?? "Unknown")
  }

  private func effectiveDetails(_ availability: EffectiveAvailability) -> some View {
    VStack(spacing: 6) {
      detailRow(
        icon: "line.3.horizontal.decrease.circle", label: "Limiting window",
        value: limitingWindowText(availability))
      detailRow(icon: "clock", label: "Reset", value: resetText(availability))
      detailRow(icon: "speedometer", label: "Pace", value: paceText(availability.pace))
      detailRow(icon: "flag.checkered", label: "Runway", value: runwayText(availability.runway))
    }
  }

  private func unresolvedDetails(_ availability: EffectiveAvailability) -> some View {
    VStack(spacing: 6) {
      if availability.pace != nil {
        detailRow(icon: "speedometer", label: "Reported pace", value: paceText(availability.pace))
      }
      if availability.runway != nil {
        detailRow(
          icon: "flag.checkered", label: "Reported runway", value: runwayText(availability.runway))
      }
    }
  }

  private var windowRows: some View {
    VStack(alignment: .leading, spacing: 7) {
      Divider().overlay(Color.white.opacity(0.07))
      Text(unresolvedRelationships ? "REPORTED WINDOWS · NOT COMBINED" : "REPORTED WINDOWS")
        .font(.system(size: 9, weight: .bold))
        .tracking(0.7)
        .foregroundStyle(QuotaPalette.secondaryText.opacity(0.8))

      ForEach(provider.windows, id: \.id) { window in
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(window.label.capitalized)
              .lineLimit(1)
            Spacer(minLength: 6)
            Text(window.percentRemaining.map { "\($0.formattedQuotaPercentage)%" } ?? "Unknown")
              .foregroundStyle(
                window.percentRemaining == nil ? QuotaPalette.neutral : QuotaPalette.primaryText
              )
              .monospacedDigit()
            Text(windowResetText(window))
              .foregroundStyle(QuotaPalette.secondaryText)
              .frame(width: 104, alignment: .trailing)
              .lineLimit(1)
          }
          if let pace = window.pace {
            Text("Pace · \(windowPaceText(pace))")
              .font(.system(size: 9.5))
              .foregroundStyle(QuotaPalette.secondaryText)
          }
        }
        .font(.system(size: 10.5))
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func detailRow(icon: String, label: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: icon)
        .frame(width: 13)
        .foregroundStyle(QuotaPalette.secondaryText)
        .accessibilityHidden(true)
      Text(label)
        .foregroundStyle(QuotaPalette.secondaryText)
      Spacer(minLength: 6)
      Text(value)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
    }
    .font(.system(size: 10.5))
    .accessibilityElement(children: .combine)
  }

  private var providerInitials: String {
    let words = provider.label.split(separator: " ")
    if words.count > 1 {
      return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    return String(provider.label.prefix(2)).uppercased()
  }

  private var providerStateText: String {
    if globallyStale {
      return "Snapshot stale · \(refreshTimestampText)"
    }
    if provider.state.reason == .keychainAccessRequired {
      return "Keychain access required"
    }
    if provider.state.authStatus == .expiredRefreshable {
      return "Credentials can be refreshed"
    }
    switch provider.state.status {
    case .fresh:
      let plan = provider.plan?.replacingOccurrences(of: "_", with: " ").capitalized
      return [plan, sourceLabel].compactMap { $0 }.joined(separator: " · ")
    case .stale:
      return "Provider data stale · \(refreshTimestampText)"
    case .authRequired:
      return "Authentication required · not in summary"
    case .rateLimited:
      return "Collection rate limited · not in summary"
    case .unavailable:
      return "Quota unavailable · not in summary"
    case .error:
      return "Collection error · not in summary"
    }
  }

  private var sourceLabel: String? {
    switch provider.source {
    case .oauth: return "OAuth"
    case .cliRPC: return "CLI"
    case .api: return "API"
    case .web: return "Web"
    case .cache: return "Cache"
    case .unavailable: return nil
    }
  }

  private var refreshTimestampText: String {
    guard let value = provider.state.refreshedAt, let date = DateParser.parse(value) else {
      return "time unknown"
    }
    return date.shortAbsoluteDate
  }

  private var scopeLabel: String {
    guard let scope = knownQuota?.availability.scope else { return "effective" }
    switch scope {
    case "all_models": return "effective · all models"
    case "all_products": return "effective · all products"
    default:
      return "effective · \(scope.replacingOccurrences(of: "_", with: " "))"
    }
  }

  private func limitingWindowText(_ availability: EffectiveAvailability) -> String {
    let ids = availability.limitingWindowIds ?? []
    let labels = ids.map(windowLabel)
    return labels.isEmpty ? "Known scope" : labels.joined(separator: " + ")
  }

  private func resetText(_ availability: EffectiveAvailability) -> String {
    let ids =
      availability.limitingWindowIds ?? availability.runway?.limitingWindowId.map { [$0] } ?? []
    let resets = ids.compactMap { id -> String? in
      guard let window = provider.windows.first(where: { $0.id == id }) else { return nil }
      return windowResetText(window)
    }
    return resets.isEmpty ? "Unknown" : resets.joined(separator: " · ")
  }

  private func paceText(_ pace: EffectivePace?) -> String {
    guard let pace else { return "Unknown" }
    switch pace.status {
    case .ahead: return "Burning faster than reset"
    case .onPace: return "On pace"
    case .behind: return "Usage below linear pace"
    case .mixed: return "Mixed across windows"
    case .unknown: return "Unknown"
    }
  }

  private func windowPaceText(_ pace: QuotaPace) -> String {
    switch pace.status {
    case .ahead: return "Burning faster than reset"
    case .onPace: return "On pace"
    case .behind: return "Usage below linear pace"
    case .unknown:
      switch pace.reason {
      case .unsupportedPeriod: return "Unavailable for this period"
      case .stale: return "Unavailable for stale data"
      default: return "Unknown"
      }
    }
  }

  private func runwayText(_ runway: EffectiveRunway?) -> String {
    guard let runway else { return "Unknown" }
    switch runway.status {
    case .exhaustedNow:
      return "Exhausted now"
    case .projectedExhaustion:
      if let seconds = runway.usableRunwaySeconds {
        return "Projected empty in \(seconds.compactDuration)"
      }
      if let rawDate = runway.projectedExhaustedAt, let date = DateParser.parse(rawDate) {
        return "Projected empty \(date.relativeDescription)"
      }
      return "Projected exhaustion"
    case .throughReset:
      return "Projected through reset"
    case .unknown:
      return "Unknown"
    }
  }

  private func windowLabel(_ id: String) -> String {
    provider.windows.first(where: { $0.id == id })?.label.capitalized
      ?? id.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func windowResetText(_ window: QuotaWindow) -> String {
    if let resetsAt = window.resetsAt, let date = DateParser.parse(resetsAt) {
      return date.relativeDescription
    }
    return window.resetText ?? "Reset unknown"
  }

  private var emptyWindowText: String {
    switch provider.state.status {
    case .authRequired:
      return "Sign in through the provider's existing credential source to collect quota."
    case .fresh: return "Provider access is usable, but no numeric quota window was reported."
    default: return "No quota window is currently available."
    }
  }
}

private enum DateParser {
  static func parse(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: value)
  }
}

extension Date {
  fileprivate var relativeDescription: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: self, relativeTo: Date())
  }

  fileprivate var shortAbsoluteDate: String {
    formatted(date: .abbreviated, time: .shortened)
  }
}

extension Double {
  fileprivate var compactDuration: String {
    let total = max(0, Int(self.rounded()))
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}
