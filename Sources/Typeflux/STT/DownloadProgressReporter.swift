import Foundation

enum DownloadProgressReporter {
    static func download(
        request: URLRequest,
        session: URLSession = .shared,
        onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws -> (URL, URLResponse) {
        guard onProgress != nil else {
            return try await session.download(for: request)
        }

        let delegate = ProgressDelegate(onProgress: onProgress)
        return try await session.download(for: request, delegate: delegate)
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Int64, Int64?) -> Void)?

    init(onProgress: (@Sendable (Int64, Int64?) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        onProgress?(totalBytesWritten, totalBytes)
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo _: URL
    ) {}
}
