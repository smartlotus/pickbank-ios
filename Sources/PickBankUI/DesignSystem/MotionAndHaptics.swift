import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum MotionTokens {
    public static let fast: Double = 0.14
    public static let standard: Double = 0.24
    public static let springInteractive = Animation.spring(response: 0.34, dampingFraction: 0.76)
    public static let springBouncy = Animation.spring(response: 0.42, dampingFraction: 0.68)
}

public enum Haptics {
    public static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    public static func medium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    public static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    public static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

public struct SpringPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: MotionTokens.fast), value: configuration.isPressed)
    }
}

public extension View {
    func numericRollTransition() -> some View {
        self.contentTransition(.numericText())
    }
}
