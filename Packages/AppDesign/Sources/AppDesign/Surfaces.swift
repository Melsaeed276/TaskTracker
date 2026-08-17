import SwiftUI

public extension View {
    /// Navigation / panel chrome. Regular glass in a continuous rounded rect on 26+;
    /// shaped `.regularMaterial` on the floor. Never Clear (docs/DESIGN_SYSTEM.md).
    @ViewBuilder
    func navigationSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Floating panel host (menu-bar window). Shaped Regular glass on 26+; shaped material on the
    /// floor. Deliberately does **not** clear the window container background - that made
    /// MenuBarExtra clicks fall through (Stop / Reset / Open Tasks appeared dead).
    @ViewBuilder
    func panelChromeSurface() -> some View {
        navigationSurface()
    }

    @ViewBuilder
    func floatingControlSurface() -> some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
    }

    @ViewBuilder
    func circularControlSurface() -> some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
    }
}
public struct SurfaceGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Surface Group") {
    SurfaceGroup {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: AppSymbols.Timer.pause)
            Text("Surface content")
        }
        .padding()
    }
    .padding()
}
#endif
