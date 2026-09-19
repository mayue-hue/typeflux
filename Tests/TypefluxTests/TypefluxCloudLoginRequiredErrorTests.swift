@testable import Typeflux
import XCTest

final class TypefluxCloudLoginRequiredErrorTests: XCTestCase {
    func testDetectsTypefluxOfficialASRRoutingUnauthorized() {
        let error = TypefluxCloudLoginRequiredError.fromError(TypefluxOfficialASRRoutingError.unauthorized)

        XCTAssertEqual(error, TypefluxCloudLoginRequiredError())
    }

    func testDetectsTypefluxOfficialASRNotLoggedIn() {
        let error = TypefluxCloudLoginRequiredError.fromError(TypefluxOfficialASRError.notLoggedIn)

        XCTAssertEqual(error, TypefluxCloudLoginRequiredError())
    }

    func testDetectsTypefluxCloudLLMNotLoggedIn() {
        let error = TypefluxCloudLoginRequiredError.fromError(TypefluxCloudLLMError.notLoggedIn)

        XCTAssertEqual(error, TypefluxCloudLoginRequiredError())
    }

    func testDetectsWrappedEndpointFailure() {
        let wrapped = CloudRequestExecutorError.allEndpointsFailed(lastError: TypefluxOfficialASRError.notLoggedIn)

        let error = TypefluxCloudLoginRequiredError.fromError(wrapped)

        XCTAssertEqual(error, TypefluxCloudLoginRequiredError())
    }

    func testDetectsWrappedIntegratedRewriteFailure() {
        let wrapped = TypefluxCloudIntegratedRewriteError(
            transcript: "hello",
            underlyingError: TypefluxCloudLLMError.notLoggedIn
        )

        let error = TypefluxCloudLoginRequiredError.fromError(wrapped)

        XCTAssertEqual(error, TypefluxCloudLoginRequiredError())
    }

    func testIgnoresUnrelatedErrors() {
        let error = NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Something else failed"]
        )

        XCTAssertNil(TypefluxCloudLoginRequiredError.fromError(error))
    }
}
