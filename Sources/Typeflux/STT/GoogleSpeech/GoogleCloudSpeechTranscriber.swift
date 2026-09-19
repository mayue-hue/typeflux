import Foundation
import GRPC
import NIO
import os

final class GoogleCloudSpeechTranscriber: TypefluxCloudScenarioAwareTranscriber, RealtimeTranscriptionSessionFactory {
    private let settingsStore: SettingsStore
    private let logger = Logger(subsystem: "ai.gulu.app.typeflux", category: "GoogleCloudSpeechTranscriber")

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func transcribeStream(
        audioFile: AudioFile,
        scenario _: TypefluxCloudScenario,
        onUpdate: @escaping @Sendable (TranscriptionSnapshot) async -> Void
    ) async throws -> String {
        let effectiveCredential = try await GoogleCloudSpeechCredentialResolver.resolveCredential(
            manualCredential: ""
        )
        let configuration = try await MainActor.run {
            try GoogleCloudSpeechConfiguration(
                projectID: settingsStore.googleCloudProjectID,
                apiKey: effectiveCredential,
                model: settingsStore.googleCloudModel,
                appLanguage: settingsStore.appLanguage
            )
        }
        let pcmData = try CloudASRAudioConverter.convert(url: audioFile.fileURL)
        return try await GoogleCloudSpeechStreamingSession.run(
            pcmData: pcmData,
            configuration: configuration,
            onUpdate: onUpdate
        )
    }

    func makeRealtimeTranscriptionSession(
        scenario _: TypefluxCloudScenario,
        onUpdate: @escaping @Sendable (TranscriptionSnapshot) async -> Void
    ) async throws -> any RealtimeTranscriptionSession {
        let effectiveCredential = try await GoogleCloudSpeechCredentialResolver.resolveCredential(
            manualCredential: ""
        )
        let configuration = try await MainActor.run {
            try GoogleCloudSpeechConfiguration(
                projectID: settingsStore.googleCloudProjectID,
                apiKey: effectiveCredential,
                model: settingsStore.googleCloudModel,
                appLanguage: settingsStore.appLanguage
            )
        }
        return BufferedRealtimeTranscriptionSession(
            upstream: GoogleCloudSpeechRealtimePCMStream(
                configuration: configuration,
                onUpdate: onUpdate
            )
        )
    }

    static func testConnection(projectID: String, apiKey: String, model: String,
                               appLanguage: AppLanguage) async throws -> String {
        _ = apiKey
        let effectiveCredential = try await GoogleCloudSpeechCredentialResolver.resolveCredential(manualCredential: "")
        let configuration = try GoogleCloudSpeechConfiguration(
            projectID: projectID,
            apiKey: effectiveCredential,
            model: model,
            appLanguage: appLanguage
        )
        return try await GoogleCloudSpeechStreamingSession.run(
            pcmData: RemoteSTTTestAudio.pcm16MonoSilence(durationMs: 300),
            configuration: configuration
        ) { _ in }
    }
}

struct GoogleCloudSpeechConfiguration: Equatable {
    enum Credential: Equatable {
        case apiKey(String)
        case bearerToken(String)
    }

    let projectID: String
    let credentialValue: String
    let model: String
    let location: String
    let endpointHost: String
    let languageCode: String
    let credential: Credential

    var recognizer: String {
        "projects/\(projectID)/locations/\(location)/recognizers/_"
    }

    var routingMetadataValue: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/&=+")
        let encodedRecognizer = recognizer.addingPercentEncoding(withAllowedCharacters: allowed) ?? recognizer
        return "recognizer=\(encodedRecognizer)"
    }

    init(projectID: String, apiKey: String, model: String, appLanguage: AppLanguage) throws {
        let trimmedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCredential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedProjectID.isEmpty else {
            throw GoogleCloudSpeechError.missingProjectID
        }
        guard !trimmedCredential.isEmpty else {
            throw GoogleCloudSpeechError.missingAPIKey
        }

        self.projectID = trimmedProjectID
        credentialValue = trimmedCredential
        credential = Self.googleCredential(for: trimmedCredential)
        self.model = trimmedModel.isEmpty ? GoogleCloudSpeechDefaults.model : trimmedModel
        location = Self.googleLocation(for: self.model)
        endpointHost = location == "global" ? "speech.googleapis.com" : "\(location)-speech.googleapis.com"
        languageCode = Self.googleLanguageCode(for: appLanguage, model: self.model)
    }

    static func googleCredential(for rawValue: String) -> Credential {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.lowercased().hasPrefix("bearer ") {
            let token = String(trimmedValue.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .bearerToken(token)
        }

        if trimmedValue.hasPrefix("AIza") {
            return .apiKey(trimmedValue)
        }

        return .bearerToken(trimmedValue)
    }

    static func googleLocation(for model: String) -> String {
        switch model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chirp_3":
            "us"
        default:
            "global"
        }
    }

    static func googleLanguageCode(for appLanguage: AppLanguage, model: String = "") -> String {
        _ = model
        return switch appLanguage {
        case .english:
            "en-US"
        case .simplifiedChinese:
            "cmn-Hans-CN"
        case .traditionalChinese:
            "cmn-Hant-TW"
        case .japanese:
            "ja-JP"
        case .korean:
            "ko-KR"
        }
    }
}

enum GoogleCloudSpeechError: LocalizedError {
    case missingProjectID
    case missingAPIKey
    case rpcFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProjectID:
            "Google Cloud Project ID is required."
        case .missingAPIKey:
            "Google Cloud access token or API key is required."
        case let .rpcFailed(message):
            "Google Cloud Speech-to-Text error: \(message)"
        }
    }
}

enum GoogleCloudSpeechStreamingSession {
    static func run(
        pcmData: Data,
        configuration: GoogleCloudSpeechConfiguration,
        onUpdate: @escaping @Sendable (TranscriptionSnapshot) async -> Void
    ) async throws -> String {
        let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
        let channel = ClientConnection.usingTLSBackedByNIOSSL(on: group)
            .connect(host: configuration.endpointHost, port: 443)

        let client = Google_Cloud_Speech_V2_SpeechAsyncClient(channel: channel)
        var callOptions = CallOptions(timeLimit: .timeout(.seconds(30)))
        applyAuthorizationMetadata(to: &callOptions, configuration: configuration)
        callOptions.customMetadata.add(
            name: "x-goog-request-params",
            value: configuration.routingMetadataValue
        )

        let responses = client.streamingRecognize(
            makeRequests(pcmData: pcmData, configuration: configuration),
            callOptions: callOptions
        )

        var finalSegments: [String] = []
        var currentPartial = ""

        do {
            for try await response in responses {
                let update = transcriptUpdate(
                    from: response,
                    finalSegments: &finalSegments,
                    currentPartial: &currentPartial
                )
                if !update.text.isEmpty {
                    await onUpdate(update)
                }
            }
        } catch {
            await shutdown(channel: channel, group: group)
            throw GoogleCloudSpeechError.rpcFailed(rpcErrorMessage(error, configuration: configuration))
        }

        let transcript = assembleTranscript(finalSegments: finalSegments, currentPartial: currentPartial)
        if !transcript.isEmpty {
            await onUpdate(TranscriptionSnapshot(text: transcript, isFinal: true))
        }
        await shutdown(channel: channel, group: group)
        return transcript
    }

    static func applyAuthorizationMetadata(
        to callOptions: inout CallOptions,
        configuration: GoogleCloudSpeechConfiguration
    ) {
        switch configuration.credential {
        case let .apiKey(apiKey):
            callOptions.customMetadata.add(name: "x-goog-api-key", value: apiKey)
        case let .bearerToken(accessToken):
            callOptions.customMetadata.add(name: "authorization", value: "Bearer \(accessToken)")
        }
    }

    static func rpcErrorMessage(_ error: Error, configuration: GoogleCloudSpeechConfiguration) -> String {
        if let status = error as? GRPCStatus {
            if status.code == .permissionDenied {
                return permissionDeniedMessage(status: status, configuration: configuration)
            }
            if let message = status.message, !message.isEmpty {
                return "\(status.code): \(message)"
            }
            return String(describing: status.code)
        }
        return error.localizedDescription
    }

    private static func permissionDeniedMessage(
        status: GRPCStatus,
        configuration: GoogleCloudSpeechConfiguration
    ) -> String {
        let backendMessage = status.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resourceHint = "recognizer \(configuration.recognizer)"

        switch configuration.credential {
        case .apiKey:
            let guidance =
                "permission denied. Google Cloud Speech-to-Text v2 StreamingRecognize usually requires an OAuth access token or Application Default Credentials instead of an API key. Make sure the authenticated principal has speech.recognizers.recognize on \(resourceHint)."
            if backendMessage.isEmpty {
                return guidance
            }
            return "\(guidance) Backend message: \(backendMessage)"

        case .bearerToken:
            let guidance =
                "permission denied. Make sure the authenticated Google principal has speech.recognizers.recognize on \(resourceHint)."
            if backendMessage.isEmpty {
                return guidance
            }
            return "\(guidance) Backend message: \(backendMessage)"
        }
    }

    private static func shutdown(channel: ClientConnection, group: EventLoopGroup) async {
        try? await channel.close().get()
        await withCheckedContinuation { continuation in
            group.shutdownGracefully { _ in
                continuation.resume()
            }
        }
    }

    private static func makeRequests(
        pcmData: Data,
        configuration: GoogleCloudSpeechConfiguration
    ) -> [Google_Cloud_Speech_V2_StreamingRecognizeRequest] {
        var requests = [makeConfigRequest(configuration: configuration)]
        requests.reserveCapacity(1 + Int(ceil(Double(pcmData.count) / Double(CloudASRAudioConverter.chunkSize))))

        var offset = pcmData.startIndex
        while offset < pcmData.endIndex {
            let end = pcmData.index(
                offset,
                offsetBy: CloudASRAudioConverter.chunkSize,
                limitedBy: pcmData.endIndex
            ) ?? pcmData.endIndex
            var request = Google_Cloud_Speech_V2_StreamingRecognizeRequest()
            request.recognizer = configuration.recognizer
            request.audio = Data(pcmData[offset ..< end])
            requests.append(request)
            offset = end
        }
        return requests
    }

    static func makeConfigRequest(
        configuration: GoogleCloudSpeechConfiguration
    ) -> Google_Cloud_Speech_V2_StreamingRecognizeRequest {
        var decodingConfig = Google_Cloud_Speech_V2_ExplicitDecodingConfig()
        decodingConfig.encoding = .linear16
        decodingConfig.sampleRateHertz = Int32(CloudASRAudioConverter.targetSampleRate)
        decodingConfig.audioChannelCount = 1

        var recognitionConfig = Google_Cloud_Speech_V2_RecognitionConfig()
        recognitionConfig.explicitDecodingConfig = decodingConfig
        recognitionConfig.model = configuration.model
        recognitionConfig.languageCodes = [configuration.languageCode]

        var features = Google_Cloud_Speech_V2_StreamingRecognitionFeatures()
        features.interimResults = true

        var streamingConfig = Google_Cloud_Speech_V2_StreamingRecognitionConfig()
        streamingConfig.config = recognitionConfig
        streamingConfig.streamingFeatures = features

        var request = Google_Cloud_Speech_V2_StreamingRecognizeRequest()
        request.recognizer = configuration.recognizer
        request.streamingConfig = streamingConfig
        return request
    }

    static func transcriptUpdate(
        from response: Google_Cloud_Speech_V2_StreamingRecognizeResponse,
        finalSegments: inout [String],
        currentPartial: inout String
    ) -> TranscriptionSnapshot {
        for result in response.results {
            guard let alternative = result.alternatives.first else { continue }
            let transcript = alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { continue }

            if result.isFinal {
                finalSegments.append(transcript)
                currentPartial = ""
            } else {
                currentPartial = transcript
            }
        }

        return TranscriptionSnapshot(
            text: assembleTranscript(finalSegments: finalSegments, currentPartial: currentPartial),
            isFinal: !finalSegments.isEmpty && currentPartial.isEmpty
        )
    }

    static func assembleTranscript(finalSegments: [String], currentPartial: String) -> String {
        (finalSegments + [currentPartial])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private actor GoogleCloudSpeechRealtimePCMStream: PCM16RealtimeTranscriptionSession {
    private typealias Request = Google_Cloud_Speech_V2_StreamingRecognizeRequest

    private let configuration: GoogleCloudSpeechConfiguration
    private let onUpdate: @Sendable (TranscriptionSnapshot) async -> Void
    private var group: EventLoopGroup?
    private var channel: ClientConnection?
    private var continuation: AsyncThrowingStream<Request, Error>.Continuation?
    private var responseTask: Task<Void, Never>?
    private var finalSegments: [String] = []
    private var currentPartial = ""
    private var streamError: Error?
    private var completed = false

    init(
        configuration: GoogleCloudSpeechConfiguration,
        onUpdate: @escaping @Sendable (TranscriptionSnapshot) async -> Void
    ) {
        self.configuration = configuration
        self.onUpdate = onUpdate
    }

    func start() async throws {
        let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
        let channel = ClientConnection.usingTLSBackedByNIOSSL(on: group)
            .connect(host: configuration.endpointHost, port: 443)
        let client = Google_Cloud_Speech_V2_SpeechAsyncClient(channel: channel)
        var callOptions = CallOptions(timeLimit: .timeout(.seconds(600)))
        GoogleCloudSpeechStreamingSession.applyAuthorizationMetadata(to: &callOptions, configuration: configuration)
        callOptions.customMetadata.add(
            name: "x-goog-request-params",
            value: configuration.routingMetadataValue
        )

        var streamContinuation: AsyncThrowingStream<Request, Error>.Continuation?
        let stream = AsyncThrowingStream<Request, Error> { continuation in
            streamContinuation = continuation
        }
        let responses = client.streamingRecognize(stream, callOptions: callOptions)
        self.group = group
        self.channel = channel
        continuation = streamContinuation

        continuation?.yield(GoogleCloudSpeechStreamingSession.makeConfigRequest(configuration: configuration))

        responseTask = Task { [weak self] in
            await self?.readResponses(responses)
        }
    }

    func appendPCM16(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        if let streamError { throw streamError }
        var request = Request()
        request.recognizer = configuration.recognizer
        request.audio = Data(data)
        continuation?.yield(request)
    }

    func finish() async throws -> String {
        continuation?.finish()
        await responseTask?.value
        if let streamError { throw streamError }
        let transcript = GoogleCloudSpeechStreamingSession.assembleTranscript(
            finalSegments: finalSegments,
            currentPartial: currentPartial
        )
        if !transcript.isEmpty {
            await onUpdate(TranscriptionSnapshot(text: transcript, isFinal: true))
        }
        await close()
        return transcript
    }

    func cancel() async {
        continuation?.finish(throwing: CancellationError())
        await close()
    }

    private func readResponses(
        _ responses: GRPCAsyncResponseStream<Google_Cloud_Speech_V2_StreamingRecognizeResponse>
    ) async {
        do {
            for try await response in responses {
                let update = GoogleCloudSpeechStreamingSession.transcriptUpdate(
                    from: response,
                    finalSegments: &finalSegments,
                    currentPartial: &currentPartial
                )
                if !update.text.isEmpty {
                    await onUpdate(update)
                }
            }
            completed = true
        } catch {
            if !Task.isCancelled {
                streamError = GoogleCloudSpeechError.rpcFailed(
                    GoogleCloudSpeechStreamingSession.rpcErrorMessage(error, configuration: configuration)
                )
            }
            completed = true
        }
    }

    private func close() async {
        responseTask?.cancel()
        responseTask = nil
        continuation = nil
        if let channel {
            try? await channel.close().get()
        }
        if let group {
            await withCheckedContinuation { continuation in
                group.shutdownGracefully { _ in
                    continuation.resume()
                }
            }
        }
        channel = nil
        group = nil
    }
}
