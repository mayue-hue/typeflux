@testable import Typeflux
import XCTest

final class PrivacyGuardTests: XCTestCase {
    // MARK: - PermissionID

    func testPermissionIDRawValues() {
        XCTAssertEqual(PrivacyGuard.PermissionID.microphone.rawValue, "microphone")
        XCTAssertEqual(PrivacyGuard.PermissionID.speechRecognition.rawValue, "speechRecognition")
        XCTAssertEqual(PrivacyGuard.PermissionID.accessibility.rawValue, "accessibility")
    }

    func testPermissionIDAllCases() {
        let allCases = PrivacyGuard.PermissionID.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.microphone))
        XCTAssertTrue(allCases.contains(.speechRecognition))
        XCTAssertTrue(allCases.contains(.accessibility))
    }

    func testPermissionIDIdentifiable() {
        for permissionID in PrivacyGuard.PermissionID.allCases {
            XCTAssertEqual(permissionID.id, permissionID.rawValue)
        }
    }

    // MARK: - PermissionState

    func testPermissionStateEquality() {
        XCTAssertEqual(PrivacyGuard.PermissionState.granted, PrivacyGuard.PermissionState.granted)
        XCTAssertEqual(PrivacyGuard.PermissionState.needsAttention, PrivacyGuard.PermissionState.needsAttention)
        XCTAssertNotEqual(PrivacyGuard.PermissionState.granted, PrivacyGuard.PermissionState.needsAttention)
    }

    // MARK: - PermissionSnapshot

    func testPermissionSnapshotGrantedProperties() {
        let snapshot = PrivacyGuard.PermissionSnapshot(
            id: .microphone,
            state: .granted,
            detail: "Microphone access is granted."
        )

        XCTAssertTrue(snapshot.isGranted)
        XCTAssertFalse(snapshot.badgeText.isEmpty)
        XCTAssertFalse(snapshot.actionTitle.isEmpty)
    }

    func testPermissionSnapshotNeedsAttentionProperties() {
        let snapshot = PrivacyGuard.PermissionSnapshot(
            id: .accessibility,
            state: .needsAttention,
            detail: "Accessibility access is needed."
        )

        XCTAssertFalse(snapshot.isGranted)
        XCTAssertFalse(snapshot.badgeText.isEmpty)
        XCTAssertFalse(snapshot.actionTitle.isEmpty)
    }

    @MainActor
    func testPermissionSnapshotLocalizedDetailTracksLanguageChanges() {
        let originalLanguage = AppLocalization.shared.language
        defer {
            AppLocalization.shared.setLanguage(originalLanguage)
        }

        let snapshot = PrivacyGuard.PermissionSnapshot(
            id: .microphone,
            state: .needsAttention,
            detailKey: "permission.microphone.detail.notDetermined"
        )

        AppLocalization.shared.setLanguage(.simplifiedChinese)
        XCTAssertEqual(snapshot.detail, "请授予麦克风权限，以便从菜单栏开始录音。")

        AppLocalization.shared.setLanguage(.english)
        XCTAssertEqual(snapshot.detail, "Grant microphone access to allow recording from the menu bar.")
    }

    // MARK: - requiredPermissionIDs

    @MainActor
    func testRequiredPermissionIDsAlwaysIncludesMicrophoneAndAccessibility() throws {
        let suiteName = "PrivacyGuardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        settings.sttProvider = .whisperAPI
        settings.useAppleSpeechFallback = false

        let ids = PrivacyGuard.requiredPermissionIDs(settingsStore: settings)
        XCTAssertTrue(ids.contains(.microphone))
        XCTAssertTrue(ids.contains(.accessibility))

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testRequiredPermissionIDsIncludesSpeechRecognitionForAppleSpeech() throws {
        let suiteName = "PrivacyGuardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        settings.sttProvider = .appleSpeech

        let ids = PrivacyGuard.requiredPermissionIDs(settingsStore: settings)
        XCTAssertTrue(ids.contains(.speechRecognition))

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testRequiredPermissionIDsIncludesSpeechRecognitionWhenFallbackEnabled() throws {
        let suiteName = "PrivacyGuardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        settings.sttProvider = .whisperAPI
        settings.useAppleSpeechFallback = true

        let ids = PrivacyGuard.requiredPermissionIDs(settingsStore: settings)
        XCTAssertTrue(ids.contains(.speechRecognition))

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testRequiredPermissionIDsExcludesSpeechRecognitionForOtherProvidersWithoutFallback() throws {
        let suiteName = "PrivacyGuardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        settings.sttProvider = .localModel
        settings.useAppleSpeechFallback = false

        let ids = PrivacyGuard.requiredPermissionIDs(settingsStore: settings)
        XCTAssertFalse(ids.contains(.speechRecognition))

        defaults.removePersistentDomain(forName: suiteName)
    }
}
