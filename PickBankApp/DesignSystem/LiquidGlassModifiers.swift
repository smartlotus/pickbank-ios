import SwiftUI

/// Adaptive Liquid Glass surface & chrome helpers.
/// Uses genuine iOS 26 Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.glassEffectID`,
/// `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`) when running on iOS 26+, and falls
/// back gracefully to a custom optical specular-rim frosted material on iOS 18.
public struct PickBankGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

public extension View {
    @ViewBuilder
    func pickbankLiquidGlass(
        in shape: some Shape = Capsule(),
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let base = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            self.glassEffect(interactive ? base.interactive() : base, in: shape)
        } else {
            self.modifier(OpticalGlassFallbackModifier(shape: AnyShape(shape), tint: tint))
        }
        #else
        self.modifier(OpticalGlassFallbackModifier(shape: AnyShape(shape), tint: tint))
        #endif
    }

    @ViewBuilder
    func pickbankGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self.matchedGeometryEffect(id: id, in: namespace)
        }
        #else
        self.matchedGeometryEffect(id: id, in: namespace)
        #endif
    }

    @ViewBuilder
    func pickbankGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.modifier(FallbackGlassButtonModifier(prominent: prominent, tint: tint))
        }
        #else
        self.modifier(FallbackGlassButtonModifier(prominent: prominent, tint: tint))
        #endif
    }
}

private struct OpticalGlassFallbackModifier: ViewModifier {
    let shape: AnyShape
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.18))
                    }
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                }
                .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
            }
    }
}

private struct FallbackGlassButtonModifier: ViewModifier {
    @Environment(\.sumPalette) private var palette
    let prominent: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .fontWeight(.semibold)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? palette.ink : palette.textPrimary)
            .background {
                Capsule()
                    .fill(prominent ? (tint ?? palette.accent) : palette.surfaceElevated.opacity(0.82))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(prominent ? 0.35 : 0.18), lineWidth: 0.75)
                    }
            }
    }
}

/// Pickbank signature card container honoring both Classic Warm Dark optical glass depth and Hermes sharp editorial registration borders.
public struct SumCard<Content: View>: View {
    @Environment(\.sumPalette) private var palette
    private let cornerRadius: CGFloat
    private let highlightAccent: Bool
    private let content: Content

    public init(
        cornerRadius: CGFloat = 22,
        highlightAccent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.highlightAccent = highlightAccent
        self.content = content()
    }

    public var body: some View {
        let effectiveRadius = palette.isHermes ? min(cornerRadius, 6) : cornerRadius
        content
            .background {
                if palette.isHermes {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: effectiveRadius)
                            .fill(palette.paper)
                            .offset(x: 3, y: 3)
                        RoundedRectangle(cornerRadius: effectiveRadius)
                            .fill(palette.surfaceElevated)
                            .overlay {
                                RoundedRectangle(cornerRadius: effectiveRadius)
                                    .strokeBorder(palette.paper.opacity(0.9), lineWidth: 0.9)
                            }
                        if highlightAccent {
                            Rectangle()
                                .fill(palette.accent)
                                .frame(width: 72, height: 2)
                                .padding(.leading, 12)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                        .fill(palette.surface.opacity(0.86))
                        .overlay {
                            RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            palette.glassBorder.opacity(highlightAccent ? 0.95 : 0.75),
                                            Color.white.opacity(0.05),
                                            palette.accent.opacity(highlightAccent ? 0.35 : 0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.85
                                )
                        }
                }
            }
    }
}
