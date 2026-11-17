import PickBankCore
import SwiftUI

public struct SumPalette: Sendable {
    public let background: Color
    public let backgroundElevated: Color
    public let surface: Color
    public let surfaceElevated: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let income: Color
    public let expense: Color
    public let transfer: Color
    public let glassOverlay: Color
    public let glassBorder: Color
    public let divider: Color
    public let accent: Color
    public let isHermes: Bool

    public static let classic = SumPalette(
        background: Color(hex: 0x000000),
        backgroundElevated: Color(hex: 0x121110),
        surface: Color(hex: 0x1B1917),
        surfaceElevated: Color(hex: 0x262321),
        textPrimary: Color(hex: 0xF5F2F0),
        textSecondary: Color(hex: 0x9B948E),
        textTertiary: Color(hex: 0x5C554F),
        income: Color(hex: 0xA5D6A7),
        expense: Color(hex: 0xFFAB91),
        transfer: Color(hex: 0xFFE082),
        glassOverlay: Color(hex: 0xFFF9F5, alpha: 0.08),
        glassBorder: Color(hex: 0xFFF9F5, alpha: 0.22),
        divider: Color(hex: 0x332F2C),
        accent: Color(hex: 0xFFB74D),
        isHermes: false
    )

    public static let hermes = SumPalette(
        background: Color(hex: 0x0000F2),
        backgroundElevated: Color(hex: 0x0000D8),
        surface: Color(hex: 0x1010D8),
        surfaceElevated: Color(hex: 0x1717C6),
        textPrimary: Color(hex: 0xF5F5F5),
        textSecondary: Color(hex: 0xC9C9EE),
        textTertiary: Color(hex: 0x9292CA),
        income: Color(hex: 0xEDFF45),
        expense: Color(hex: 0xFF8A9A),
        transfer: Color(hex: 0xF5F5F5),
        glassOverlay: Color(hex: 0xF5F5F5, alpha: 0.12),
        glassBorder: Color(hex: 0xF5F5F5, alpha: 0.45),
        divider: Color(hex: 0xF5F5F5, alpha: 0.35),
        accent: Color(hex: 0xEDFF45),
        isHermes: true
    )

    public static func palette(for mode: AppThemeMode) -> SumPalette {
        mode == .hermes ? .hermes : .classic
    }

    public var paper: Color { isHermes ? Color(hex: 0xF5F5F5) : textPrimary }
    public var ink: Color { isHermes ? Color(hex: 0x0000F2) : background }
}

private struct PaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue: SumPalette = .classic
}

public extension EnvironmentValues {
    var sumPalette: SumPalette {
        get { self[PaletteEnvironmentKey.self] }
        set { self[PaletteEnvironmentKey.self] = newValue }
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Editorial Typography matching Pickbank's serif/mono contrast in Hermes mode and rounded tabular-nums in Classic mode.
public enum SumFont {
    public static func display(_ size: CGFloat, hermes: Bool) -> Font {
        if hermes {
            return .system(size: size, weight: .light, design: .serif)
        }
        return .system(size: size, weight: .bold, design: .monospaced)
    }

    public static func heading(_ size: CGFloat, hermes: Bool) -> Font {
        if hermes {
            return .system(size: size, weight: .regular, design: .serif)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Hermes editorial particle constellation + subtle etched orbital field rendered in a single pointer-transparent Canvas.
public struct SumAmbientField: View {
    let palette: SumPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(palette: SumPalette) {
        self.palette = palette
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 10 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                if palette.isHermes {
                    // Subtle etched concentric orbital lines
                    let center = CGPoint(x: size.width * 0.78, y: size.height * 0.16)
                    for ring in 1...3 {
                        let radius = CGFloat(ring) * min(size.width, size.height) * 0.24
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(palette.paper.opacity(0.08)), lineWidth: 0.8)
                    }
                    // 44 drifting paper flecks & sparse acid-yellow sparks
                    for i in 0..<44 {
                        let seed = Double(i) * 1.6180339
                        let baseX = (seed * 197.3).truncatingRemainder(dividingBy: 1.0)
                        let baseY = (seed * 311.7).truncatingRemainder(dividingBy: 1.0)
                        let driftY = (baseY - t * (0.012 + Double(i % 5) * 0.003)).truncatingRemainder(dividingBy: 1.0)
                        let wrappedY = driftY < 0 ? driftY + 1.0 : driftY
                        let swayX = sin(t * 0.6 + Double(i)) * 0.012
                        let pt = CGPoint(x: CGFloat(baseX + swayX) * size.width, y: CGFloat(wrappedY) * size.height)
                        let r = CGFloat(0.8 + Double(i % 4) * 0.45)
                        let isAcid = (i % 7 == 0)
                        let color = isAcid ? palette.accent.opacity(0.65) : palette.paper.opacity(0.28)
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)), with: .color(color))
                    }
                } else {
                    // Classic Warm Dark subtle ambient warm amber & cool glass atmospheric orbs for Liquid Glass refraction depth
                    let g1 = Gradient(colors: [Color(hex: 0xFFB74D, alpha: 0.12), .clear])
                    let p1 = CGPoint(x: size.width * (0.22 + 0.04 * sin(t * 0.18)), y: size.height * 0.15)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: p1.x - 220, y: p1.y - 220, width: 440, height: 440)),
                        with: .radialGradient(g1, center: p1, startRadius: 10, endRadius: 220)
                    )
                    let g2 = Gradient(colors: [Color(hex: 0xA5D6A7, alpha: 0.07), .clear])
                    let p2 = CGPoint(x: size.width * (0.82 + 0.03 * cos(t * 0.14)), y: size.height * 0.72)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: p2.x - 240, y: p2.y - 240, width: 480, height: 480)),
                        with: .radialGradient(g2, center: p2, startRadius: 10, endRadius: 240)
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
