import CoreData
import Foundation
import os
import SwiftData

private let spikeR1Logger = Logger(
    subsystem: "com.diwan.TaskTracker",
    category: "SpikeR1"
)

public enum AppDataModelContainer: Sendable {
    /// The private CloudKit container mirrored by `makeSynced()`. Matches the entitlement
    /// declared on each app target once signing is configured (see docs/ICLOUD_SYNC.md).
    public static let cloudKitContainerIdentifier = "iCloud.com.diwan.TaskTracker"

    /// Posted on the main actor after a completed remote-import batch (another device's data has
    /// been mirrored into the local store). `AppData` has no visibility into `AppFeature`'s
    /// controllers by design (see AGENTS.md dependency rules) — the app layer, which already
    /// imports both, is expected to observe this and call `reload()` on whichever controllers are
    /// live. Carries no payload: CloudKit's mirroring notification does not surface per-record IDs
    /// (see the `SpikeR1CloudKitObserver` comment below), so a reload is a "refresh everything you
    /// have," not a targeted update.
    public static let remoteChangeNotification = Notification.Name("AppData.remoteChangeNotification")

    @MainActor
    public static func makeLocalInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TaskRecord.self,
            TimerEventRecord.self,
            TaskTimeAdjustmentRecord.self,
            TaskSessionExclusionRecord.self,
            configurations: config
        )
    }

    /// Local on-disk container without CloudKit mirroring. Primarily used by integration tests
    /// that need to exercise real sqlite-backed fetch/save behavior.
    @MainActor
    public static func makeLocalOnDisk(storeURL: URL) throws -> ModelContainer {
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: TaskRecord.self,
            TimerEventRecord.self,
            TaskTimeAdjustmentRecord.self,
            TaskSessionExclusionRecord.self,
            configurations: config
        )
    }

    /// The production container: on-disk storage mirrored to the private CloudKit database.
    /// Both `TaskRecord` and `TimerEventRecord` have no relationships, no unique attributes, and
    /// every stored property is optional or defaulted — the CloudKit mirroring contract SwiftData
    /// requires (see AGENTS.md, docs/ICLOUD_SYNC.md). Requires the app target's entitlement for
    /// `cloudKitContainerIdentifier` to be configured before this will actually sync; until then it
    /// still works as a local on-disk store (SwiftData reports sync errors, not construction
    /// failures, when the entitlement is missing).
    @MainActor
    public static func makeSynced() throws -> ModelContainer {
        SpikeR1CloudKitObserver.shared.install()
        let config = ModelConfiguration(
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(
            for: TaskRecord.self,
            TimerEventRecord.self,
            TaskTimeAdjustmentRecord.self,
            TaskSessionExclusionRecord.self,
            configurations: config
        )
    }

    static func shouldPostRemoteChangeNotification(
        eventType: NSPersistentCloudKitContainer.EventType,
        succeeded: Bool,
        endDate: Date?
    ) -> Bool {
        eventType == .import && succeeded && endDate != nil
    }
}

// SwiftData has no first-class CloudKit observer. Apple DTS: SwiftData + CloudKit is
// NSPersistentCloudKitContainer, so the supported hook is eventChangedNotification
// (https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/eventchangednotification,
// forums/763876). Event carries type/identifier/storeIdentifier/succeeded/startDate/endDate/error —
// not per-record TimerEvent.id or originating deviceID. `.import` with a non-nil endDate is the
// remote-change batch; we log what the API surfaces and do not invent record-level fields.
@MainActor
private final class SpikeR1CloudKitObserver: NSObject {
    static let shared = SpikeR1CloudKitObserver()

    private var isInstalled = false

    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudKitEventChanged(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil
        )
    }

    @objc nonisolated private func cloudKitEventChanged(_ notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else {
            return
        }
        let observedAt = Date()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let typeName: String
        switch event.type {
        case .setup: typeName = "setup"
        case .import: typeName = "import"
        case .export: typeName = "export"
        @unknown default: typeName = "unknown"
        }
        let endDate = event.endDate.map { $0.formatted(iso) } ?? "nil"
        let errorDescription = event.error.map { String(describing: $0) } ?? "nil"
        spikeR1Logger.info(
            "spike_r1_cloudkit_event type=\(typeName, privacy: .public) cloudKitEventID=\(event.identifier.uuidString, privacy: .public) storeID=\(event.storeIdentifier, privacy: .public) succeeded=\(event.succeeded) startDate=\(event.startDate.formatted(iso), privacy: .public) endDate=\(endDate, privacy: .public) error=\(errorDescription, privacy: .public) observedAt=\(observedAt.formatted(iso), privacy: .public)"
        )

        // Only a *completed* import (not setup/export, not still in progress) means new mirrored
        // data actually landed in the local store — that's the only case a UI reload is warranted.
        if AppDataModelContainer.shouldPostRemoteChangeNotification(
            eventType: event.type,
            succeeded: event.succeeded,
            endDate: event.endDate
        ) {
            Task { @MainActor in
                NotificationCenter.default.post(name: AppDataModelContainer.remoteChangeNotification, object: nil)
            }
        }
    }
}

