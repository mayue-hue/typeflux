@testable import Typeflux
import XCTest

@MainActor
final class LocalNotificationTriggerTests: XCTestCase {
    func testPrepareOllamaModelSendsReadyNotificationOnSuccess() async throws {
        let notificationService = RecordingLocalNotificationService()
        let viewModel = try StudioViewModel(
            settingsStore: SettingsStore(
                defaults: XCTUnwrap(UserDefaults(
                    suiteName: "LocalNotificationTriggerTests.ollama.\(UUID().uuidString)"
                ))
            ),
            historyStore: InMemoryNotificationHistoryStore(),
            initialSection: .models,
            modelManager: MockOllamaModelManager(),
            localModelManager: MockLocalSTTModelManager(),
            notificationService: notificationService
        )

        viewModel.prepareOllamaModel()

        try await waitForNotificationCount(1, in: notificationService)
        let firstNotification = await notificationService.firstNotification()
        let notification = try XCTUnwrap(firstNotification)
        XCTAssertEqual(notification.title, L("notification.localModelReady.title"))
        XCTAssertEqual(notification.body, L("notification.localModelReady.body"))
        XCTAssertEqual(notification.identifier, "ai.gulu.app.typeflux.local-model-ready")
    }

    func testPrepareLocalSTTModelSendsReadyNotificationOnSuccess() async throws {
        let notificationService = RecordingLocalNotificationService()
        let localModelManager = MockLocalSTTModelManager()
        let viewModel = try StudioViewModel(
            settingsStore: SettingsStore(
                defaults: XCTUnwrap(UserDefaults(
                    suiteName: "LocalNotificationTriggerTests.localSTT.\(UUID().uuidString)"
                ))
            ),
            historyStore: InMemoryNotificationHistoryStore(),
            initialSection: .models,
            modelManager: MockOllamaModelManager(),
            localModelManager: localModelManager,
            notificationService: notificationService
        )

        viewModel.prepareLocalSTTModel()

        try await waitForNotificationCount(1, in: notificationService)
        XCTAssertEqual(localModelManager.prepareCallCount, 1)
        let firstNotification = await notificationService.firstNotification()
        let notification = try XCTUnwrap(firstNotification)
        XCTAssertEqual(notification.title, L("notification.localModelReady.title"))
        XCTAssertEqual(notification.body, L("notification.localModelReady.body"))
    }

    func testDeleteLocalSTTModelKeepsBundledModelReady() throws {
        let bundledInfo = LocalSTTPreparedModelInfo(
            storagePath: "/Applications/Typeflux.app/Contents/Resources/BundledModels/senseVoiceSmall/sensevoice-small",
            sourceDisplayName: L("common.bundled")
        )
        let localModelManager = BundledLocalSTTModelManager(preparedInfo: bundledInfo)
        let viewModel = try StudioViewModel(
            settingsStore: SettingsStore(
                defaults: XCTUnwrap(UserDefaults(
                    suiteName: "LocalNotificationTriggerTests.bundledDelete.\(UUID().uuidString)"
                ))
            ),
            historyStore: InMemoryNotificationHistoryStore(),
            initialSection: .models,
            modelManager: MockOllamaModelManager(),
            localModelManager: localModelManager,
            notificationService: RecordingLocalNotificationService()
        )

        viewModel.deleteLocalSTTModel(.senseVoiceSmall)

        XCTAssertTrue(viewModel.isLocalSTTPrepared)
        XCTAssertEqual(viewModel.localSTTPreparedSource, L("common.bundled"))
        XCTAssertEqual(viewModel.localSTTStoragePath, bundledInfo.storagePath)
        XCTAssertEqual(viewModel.toastMessage, L("settings.models.localSTT.ready"))
    }

    private func waitForNotificationCount(
        _ expectedCount: Int,
        in service: RecordingLocalNotificationService
    ) async throws {
        for _ in 0 ..< 50 {
            if await service.notificationCount() == expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(expectedCount) local notification(s)")
    }
}

private final class MockOllamaModelManager: OllamaModelManaging {
    func ensureModelReady(settingsStore _: SettingsStore) async throws {}
}

private final class MockLocalSTTModelManager: LocalSTTModelManaging {
    private(set) var prepareCallCount = 0

    func prepareModel(
        settingsStore _: SettingsStore,
        onUpdate: (@Sendable (LocalSTTPreparationUpdate) -> Void)?
    ) async throws {
        prepareCallCount += 1
        onUpdate?(LocalSTTPreparationUpdate(
            message: "ready",
            progress: 1,
            storagePath: "/tmp/typeflux-local-model",
            source: "test"
        ))
    }

    func preparedModelInfo(settingsStore _: SettingsStore) -> LocalSTTPreparedModelInfo? {
        nil
    }

    func isModelAvailable(_: LocalSTTModel) -> Bool {
        false
    }

    func deleteModelFiles(_: LocalSTTModel) throws {}

    func storagePath(for _: LocalSTTConfiguration) -> String {
        "/tmp/typeflux-local-model"
    }
}

private final class BundledLocalSTTModelManager: LocalSTTModelManaging {
    private let preparedInfo: LocalSTTPreparedModelInfo

    init(preparedInfo: LocalSTTPreparedModelInfo) {
        self.preparedInfo = preparedInfo
    }

    func prepareModel(
        settingsStore _: SettingsStore,
        onUpdate _: (@Sendable (LocalSTTPreparationUpdate) -> Void)?
    ) async throws {}

    func preparedModelInfo(settingsStore _: SettingsStore) -> LocalSTTPreparedModelInfo? {
        preparedInfo
    }

    func isModelAvailable(_: LocalSTTModel) -> Bool {
        true
    }

    func deleteModelFiles(_: LocalSTTModel) throws {}

    func storagePath(for _: LocalSTTConfiguration) -> String {
        preparedInfo.storagePath
    }
}

private actor RecordingLocalNotificationService: LocalNotificationSending {
    struct NotificationRecord {
        let title: String
        let body: String
        let identifier: String
    }

    private(set) var notifications: [NotificationRecord] = []

    func sendLocalNotification(title: String, body: String, identifier: String) async {
        notifications.append(NotificationRecord(title: title, body: body, identifier: identifier))
    }

    func notificationCount() -> Int {
        notifications.count
    }

    func firstNotification() -> NotificationRecord? {
        notifications.first
    }
}

private final class InMemoryNotificationHistoryStore: HistoryStore {
    func save(record _: HistoryRecord) {}
    func list() -> [HistoryRecord] {
        []
    }

    func list(limit _: Int, offset _: Int, searchQuery _: String?) -> [HistoryRecord] {
        []
    }

    func record(id _: UUID) -> HistoryRecord? {
        nil
    }

    func delete(id _: UUID) {}
    func purge(olderThanDays _: Int) {}
    func clear() {}
    func exportMarkdown() throws -> URL {
        URL(fileURLWithPath: "/tmp/typeflux-history.md")
    }
}
