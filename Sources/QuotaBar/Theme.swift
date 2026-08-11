import QuotaBarCore
import SwiftUI

enum QuotaPalette {
  static let healthy = Color(red: 101 / 255, green: 214 / 255, blue: 163 / 255)
  static let caution = Color(red: 244 / 255, green: 201 / 255, blue: 107 / 255)
  static let critical = Color(red: 255 / 255, green: 127 / 255, blue: 135 / 255)
  static let neutral = Color(red: 139 / 255, green: 145 / 255, blue: 166 / 255)
  static let primaryText = Color(red: 246 / 255, green: 247 / 255, blue: 251 / 255)
  static let secondaryText = Color(red: 174 / 255, green: 180 / 255, blue: 196 / 255)
  static let background = Color(red: 23 / 255, green: 25 / 255, blue: 33 / 255)
}

extension QuotaSignal {
  var color: Color {
    switch self {
    case .healthy: return QuotaPalette.healthy
    case .caution: return QuotaPalette.caution
    case .critical: return QuotaPalette.critical
    case .neutral: return QuotaPalette.neutral
    }
  }
}

struct StatusRingView: View {
  let signal: QuotaSignal

  var body: some View {
    Circle()
      .stroke(signal.color, lineWidth: 3)
      .frame(width: 14, height: 14)
      .padding(.horizontal, 3)
      .contentShape(Rectangle())
  }
}

struct QuotaCardBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(
        Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color.white.opacity(0.075), lineWidth: 1)
      }
  }
}
