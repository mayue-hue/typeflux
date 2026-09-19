import Foundation

struct TypefluxCloudASRDirectiveError: LocalizedError, Equatable {
    static let localFallbackRequiredCode = "ASR_LOCAL_FALLBACK_REQUIRED"

    var errorDescription: String? {
        L("workflow.typefluxCloud.localFallbackRequired")
    }

    static func fromServerCode(_ code: String) -> TypefluxCloudASRDirectiveError? {
        normalized(code) == localFallbackRequiredCode ? TypefluxCloudASRDirectiveError() : nil
    }

    static func fromMessage(_ message: String) -> TypefluxCloudASRDirectiveError? {
        normalized(message).contains(localFallbackRequiredCode) ? TypefluxCloudASRDirectiveError() : nil
    }

    static func fromError(_ error: Error) -> TypefluxCloudASRDirectiveError? {
        if error is TypefluxCloudASRDirectiveError {
            return TypefluxCloudASRDirectiveError()
        }
        if let executorError = error as? CloudRequestExecutorError,
           case let .allEndpointsFailed(lastError) = executorError {
            return fromError(lastError)
        }
        if let integratedError = error as? TypefluxCloudIntegratedRewriteError {
            return fromError(integratedError.underlyingError)
        }
        if let routingError = error as? TypefluxOfficialASRRoutingError,
           case let .serverError(code, message) = routingError {
            return fromServerCode(code) ?? message.flatMap(fromMessage)
        }
        if let asrError = error as? TypefluxOfficialASRError,
           case let .serverError(message) = asrError {
            return fromMessage(message)
        }
        return fromMessage(error.localizedDescription)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()
    }
}
