import Foundation
import UserNotifications

protocol LocalNotificationSending: Sendable {
    func sendLocalNotification(title: String, body: String, identifier: String) async
}

struct NoopLocalNotificationService: LocalNotificationSending {
    func sendLocalNotification(title _: String, body _: String, identifier _: String) async {}
}

final class SystemLocalNotificationService: NSObject, LocalNotificationSending, UNUserNotificationCenterDelegate,
    @unchecked Sendable {
    static let shared = SystemLocalNotificationService()

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.delegate = self
    }

    func sendLocalNotification(title: String, body: String, identifier: String) async {
        do {
            let granted = try await requestAuthorizationIfNeeded()
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try await add(request)
        } catch {
            NetworkDebugLogger.logError(context: "Local notification failed", error: error)
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func requestAuthorizationIfNeeded() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
