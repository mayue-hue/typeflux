import Foundation

struct TypefluxCloudLoginRequiredError: LocalizedError, Equatable {
    var errorDescription: String? {
        L("workflow.typefluxCloud.loginRequired")
    }

    static func fromError(_ error: Error) -> TypefluxCloudLoginRequiredError? {
        if error is TypefluxCloudLoginRequiredError {
            return TypefluxCloudLoginRequiredError()
        }

        if let executorError = error as? CloudRequestExecutorError,
           case let .allEndpointsFailed(lastError) = executorError {
            return fromError(lastError)
        }

        if let integratedRewriteError = error as? TypefluxCloudIntegratedRewriteError {
            return fromError(integratedRewriteError.underlyingError)
        }

        if let routingError = error as? TypefluxOfficialASRRoutingError,
           case .unauthorized = routingError {
            return TypefluxCloudLoginRequiredError()
        }

        if let asrError = error as? TypefluxOfficialASRError,
           case .notLoggedIn = asrError {
            return TypefluxCloudLoginRequiredError()
        }

        if let llmError = error as? TypefluxCloudLLMError,
           case .notLoggedIn = llmError {
            return TypefluxCloudLoginRequiredError()
        }

        return nil
    }
}
