import Foundation

/// Protocol for post-processing text output before injection or clipboard operations.
protocol OutputPostProcessing: Sendable {
    /// Process the given text and return the transformed result.
    /// - Parameter text: The original text to process
    /// - Returns: The processed text, or the original text if processing fails
    func process(_ text: String) async -> String
}

/// A no-op post-processor that returns text unchanged.
final class NoopOutputPostProcessor: OutputPostProcessing {
    func process(_ text: String) async -> String {
        text
    }
}
