import SwiftUI

/// Three-way tab container: 26+ gets sidebar-adaptable + minimize-on-scroll; iOS 18–25 gets
/// sidebar-adaptable alone; the iOS 17 floor gets a plain `TabView`. Feature code never branches.
///
/// Pass `selection` when the app needs programmatic tab changes (Live Activity deep link,
/// start-timer-from-task → Timer tab).
public struct AppTabView<SelectionValue: Hashable, Content: View>: View {
    @Binding private var selection: SelectionValue
    private let content: Content

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self._selection = selection
        self.content = content()
    }

    public var body: some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            TabView(selection: $selection) { content }
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 18, *) {
            TabView(selection: $selection) { content }
                .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $selection) { content }
        }
        #elseif os(macOS)
        if #available(macOS 15, *) {
            TabView(selection: $selection) { content }
                .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $selection) { content }
        }
        #else
        TabView(selection: $selection) { content }
        #endif
    }
}
#if DEBUG
private struct AppTabViewPreview: View {
    @State var selection = 0

    var body: some View {
        AppTabView(selection: $selection) {
            Text("Timer")
                .tabItem { Label("Timer", systemImage: AppSymbols.Navigation.timer) }
                .tag(0)
            Text("Today")
                .tabItem { Label("Today", systemImage: AppSymbols.Navigation.today) }
                .tag(1)
        }
    }
}

#Preview {
    AppTabViewPreview()
}
#endif
