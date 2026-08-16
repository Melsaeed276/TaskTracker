import Foundation

/// Runs a single app-lifetime expiry refresh loop for `ActiveTimerController`.
/// Keeping this outside SwiftUI views prevents render-triggered feedback loops.
@MainActor
public final class ActiveTimerExpiryRefreshLoop {
    private let timer: ActiveTimerController
    private let interval: Duration
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?

    public init(
        timer: ActiveTimerController,
        interval: Duration = .seconds(1),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.timer = timer
        self.interval = interval
        self.now = now
    }

    public func start() {
        guard task == nil else { return }
        task = Task { @MainActor [timer, interval, now] in
            while !Task.isCancelled {
                await timer.reloadIfExpired(at: now())
                try? await Task.sleep(for: interval)
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
