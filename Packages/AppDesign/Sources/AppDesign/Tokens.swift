import SwiftUI

public enum AppSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
}

public enum AppRadius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 16
}

public enum AppDuration {
    public static let fast: TimeInterval = 0.15
    public static let normal: TimeInterval = 0.25
    public static let slow: TimeInterval = 0.4
}

public enum AppearancePreference: String, CaseIterable, Sendable {
    case auto
    case light
    case dark

    public static let storageKey = "com.tasktracker.appearance"

    public var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum TimerDisplayTokens {
    public static let stopwatchHandColor: Color = .orange
    public static let stopwatchEndTimeColor: Color = .red
    public static let timerPauseRingColor: Color = .orange

    public static func timerListRemainingFont(size: CGFloat) -> Font {
        .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
    }
}
