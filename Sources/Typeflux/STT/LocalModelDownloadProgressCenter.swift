import Foundation

extension Notification.Name {
    static let localModelDownloadProgressDidChange = Notification.Name(
        "LocalModelDownloadProgressCenter.progressDidChange"
    )
}

enum LocalModelDownloadProgressStatus: Equatable {
    case idle
    case downloading(model: LocalSTTModel, progress: Double)
    case failed(model: LocalSTTModel, message: String)
}

final class LocalModelDownloadProgressCenter {
    static let shared = LocalModelDownloadProgressCenter()

    private let lock = NSLock()
    private var currentStatus: LocalModelDownloadProgressStatus = .idle

    var status: LocalModelDownloadProgressStatus {
        lock.withLock { currentStatus }
    }

    func reportDownloading(model: LocalSTTModel, progress: Double) {
        let clampedProgress = min(max(progress, 0), 1)
        updateStatus(.downloading(model: model, progress: clampedProgress))
    }

    func reportFailed(model: LocalSTTModel, message: String) {
        updateStatus(.failed(model: model, message: message))
    }

    func clear() {
        updateStatus(.idle)
    }

    private func updateStatus(_ newStatus: LocalModelDownloadProgressStatus) {
        let needsNotify = lock.withLock { () -> Bool in
            let needsNotify = currentStatus != newStatus
            currentStatus = newStatus
            return needsNotify
        }
        if needsNotify {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .localModelDownloadProgressDidChange, object: self)
            }
        }
    }
}
