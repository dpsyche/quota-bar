import AppKit
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
    Image(nsImage: StatusRingImage.make(signal: signal))
      .renderingMode(.original)
  }
}

/// Explicit 1x/2x representations keep the three-point stroke inside the canvas.
/// MenuBarExtra needs an Image leaf: a Shape can bridge to an empty native button.
@MainActor
enum StatusRingImage {
  static func make(signal: QuotaSignal) -> NSImage {
    let size = NSSize(width: 20, height: 18)
    let image = NSImage(size: size)
    for scale in [1, 2] {
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 20 * scale, pixelsHigh: 18 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      )!
      bitmap.size = size
      NSGraphicsContext.saveGraphicsState()
      let context = NSGraphicsContext(bitmapImageRep: bitmap)!
      NSGraphicsContext.current = context
      // NSGraphicsContext derives the pixel scale from bitmap.size.
      context.cgContext.clear(CGRect(origin: .zero, size: size))
      NSColor(signal.color).setStroke()
      let ring = NSBezierPath(ovalIn: NSRect(x: 3.5, y: 2.5, width: 13, height: 13))
      ring.lineWidth = 3
      ring.stroke()
      NSGraphicsContext.restoreGraphicsState()
      image.addRepresentation(bitmap)
    }
    image.isTemplate = false
    return image
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
