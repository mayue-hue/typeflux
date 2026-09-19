import Foundation

extension OpenAICompatibleAgentService: LLMMultiTurnService {
    func complete(
        messages: [AgentMessage],
        tools: [LLMAgentTool],
        config: LLMCallConfig
    ) async throws -> AgentTurnResult {
        let llmConfig = settingsStore.textLLMConfiguration()
        let connection = try await resolveConnection(for: llmConfig)
        let additionalHeaders = connection.headers(for: .askAnything)

        return try await RequestRetry.perform(operationName: "LLM multi-turn complete") {
            switch connection.provider.apiStyle {
            case .openAICompatible:
                try await self.multiTurnOpenAI(
                    provider: connection.provider,
                    baseURL: connection.baseURL,
                    model: connection.model,
                    apiKey: connection.apiKey,
                    additionalHeaders: additionalHeaders,
                    messages: messages,
                    tools: tools,
                    config: config
                )
            case .anthropic:
                try await self.multiTurnAnthropic(
                    baseURL: connection.baseURL,
                    model: connection.model,
                    apiKey: connection.apiKey,
                    additionalHeaders: additionalHeaders,
                    messages: messages,
                    tools: tools,
                    config: config
                )
            case .gemini:
                try await self.multiTurnGemini(
                    baseURL: connection.baseURL,
                    model: connection.model,
                    apiKey: connection.apiKey,
                    additionalHeaders: additionalHeaders,
                    messages: messages,
                    tools: tools,
                    config: config
                )
            }
        }
    }

    // MARK: - OpenAI Compatible

    private func multiTurnOpenAI(
        provider: LLMRemoteProvider,
        baseURL: URL,
        model: String,
        apiKey: String,
        additionalHeaders: [String: String],
        messages: [AgentMessage],
        tools: [LLMAgentTool],
        config: LLMCallConfig
    ) async throws -> AgentTurnResult {
        let url = OpenAIEndpointResolver.resolve(from: baseURL, path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        AgentRequestConfiguration.apply(to: &request)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        var body = buildOpenAIBody(model: model, messages: messages, tools: tools, config: config)
        OpenAICompatibleResponseSupport.applyProviderTuning(
            body: &body,
            baseURL: baseURL,
            model: model,
            provider: provider
        )
        let baseBody = body
        let tuningCandidate = RemoteLLMClient.applyCustomThinkingTuning(
            body: &body,
            provider: provider,
            baseURL: baseURL
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let result = try await RemoteLLMClient.performJSONRequestWithCustomThinkingAdaptation(
            request,
            baseBody: baseBody,
            provider: provider,
            baseURL: baseURL,
            candidate: tuningCandidate
        )
        let rawText = LLMAgentResponseSupport.extractOpenAICompatibleText(from: result.data) ?? ""
        let containsThinking = OpenAICompatibleResponseSupport.containsLeadingThinkingTags(rawText)
        let turnResult = parseOpenAITurnResult(from: result.data)
        if !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            RemoteLLMClient.recordCustomThinkingTuningSuccess(
                provider: provider,
                baseURL: baseURL,
                candidate: result.candidate,
                containsThinking: containsThinking
            )
        }
        return turnResult
    }

    func buildOpenAIBody(
        model: String,
        messages: [AgentMessage],
        tools: [LLMAgentTool],
        config: LLMCallConfig
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": AgentMessage.toOpenAIMessages(messages),
            "parallel_tool_calls": config.parallelToolCalls,
            "tools": tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.inputSchema.jsonObject
                    ]
                ] as [String: Any]
            }
        ]

        if let forcedTool = config.forcedToolName {
            body["tool_choice"] = [
                "type": "function",
                "function": ["name": forcedTool]
            ]
        }

        if let temp = config.temperature {
            body["temperature"] = temp
        }

        return body
    }

    func parseOpenAITurnResult(from data: Data) -> AgentTurnResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (object["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any]
        else {
            return AgentTurnResult(turn: .text(""), tokenUsage: nil)
        }

        let rawText = OpenAICompatibleResponseSupport.extractTextDelta(from: data) ?? ""
        let text = OpenAICompatibleResponseSupport.stripLeadingThinkingTags(rawText)
        let toolCallsRaw = message["tool_calls"] as? [[String: Any]] ?? []

        let tokenUsage = parseOpenAITokenUsage(from: object)

        let turn: AgentTurn
        if toolCallsRaw.isEmpty {
            turn = .text(text)
        } else {
            let toolCalls = toolCallsRaw.compactMap { raw -> AgentToolCall? in
                guard let fn = raw["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let args = fn["arguments"] as? String
                else {
                    return nil
                }
                let id = raw["id"] as? String ?? UUID().uuidString
                return AgentToolCall(id: id, name: name, argumentsJSON: args)
            }
            if text.isEmpty {
                turn = .toolCalls(toolCalls)
            } else {
                turn = .textWithToolCalls(text: text, toolCalls: toolCalls)
            }
        }

        return AgentTurnResult(turn: turn, tokenUsage: tokenUsage)
    }

    /// Legacy helper kept for backward compatibility with tests.
    func parseOpenAITurn(from data: Data) -> AgentTurn {
        parseOpenAITurnResult(from: data).turn
    }

    private func parseOpenAITokenUsage(from object: [String: Any]) -> LLMTokenUsage? {
        guard let usage = object["usage"] as? [String: Any],
              let promptTokens = usage["prompt_tokens"] as? Int,
              let completionTokens = usage["completion_tokens"] as? Int
        else {
            return nil
        }
        let totalTokens = usage["total_tokens"] as? Int ?? (promptTokens + completionTokens)
        return LLMTokenUsage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens
        )
    }

    // MARK: - Anthropic

    private func multiTurnAnthropic(
        baseURL: URL,
        model: String,
        apiKey: String,
        additionalHeaders: [String: String],
        messages: [AgentMessage],
        tools: [LLMAgentTool],
        config: LLMCallConfig
    ) async throws -> AgentTurnResult {
        let url = OpenAIEndpointResolver.resolve(from: baseURL, path: "messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        AgentRequestConfiguration.apply(to: &request)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let anthropicMessages = AgentMessage.toAnthropicMessages(messages)
        let systemPrompt = AgentMessage.extractAnthropicSystemPrompt(messages)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": anthropicMessages,
            "tools": tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema.jsonObject
                ] as [String: Any]
            }
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        if let forcedTool = config.forcedToolName {
            body["tool_choice"] = ["type": "tool", "name": forcedTool]
        }

        if let temp = config.temperature {
            body["temperature"] = temp
        }

        OpenAICompatibleResponseSupport.applyAnthropicTuning(body: &body)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await RemoteLLMClient.performJSONRequest(request)
        return parseAnthropicTurnResult(from: data)
    }

    func parseAnthropicTurnResult(from data: Data) -> AgentTurnResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]]
        else {
            return AgentTurnResult(turn: .text(""), tokenUsage: nil)
        }

        var text = ""
        var toolCalls: [AgentToolCall] = []

        for block in content {
            let type = block["type"] as? String ?? ""
            if type == "text", let t = block["text"] as? String {
                text += t
            } else if type == "tool_use" {
                guard let name = block["name"] as? String,
                      let id = block["id"] as? String,
                      let input = block["input"],
                      JSONSerialization.isValidJSONObject(input),
                      let inputData = try? JSONSerialization.data(withJSONObject: input),
                      let argsJSON = String(data: inputData, encoding: .utf8)
                else {
                    continue
                }
                toolCalls.append(AgentToolCall(id: id, name: name, argumentsJSON: argsJSON))
            }
        }

        let tokenUsage = parseAnthropicTokenUsage(from: object)

        let turn: AgentTurn = if toolCalls.isEmpty {
            .text(text)
        } else if text.isEmpty {
            .toolCalls(toolCalls)
        } else {
            .textWithToolCalls(text: text, toolCalls: toolCalls)
        }

        return AgentTurnResult(turn: turn, tokenUsage: tokenUsage)
    }

    /// Legacy helper kept for backward compatibility with tests.
    func parseAnthropicTurn(from data: Data) -> AgentTurn {
        parseAnthropicTurnResult(from: data).turn
    }

    private func parseAnthropicTokenUsage(from object: [String: Any]) -> LLMTokenUsage? {
        guard let usage = object["usage"] as? [String: Any] else { return nil }
        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return LLMTokenUsage(
            promptTokens: inputTokens,
            completionTokens: outputTokens,
            totalTokens: inputTokens + outputTokens
        )
    }

    // MARK: - Gemini

    private func multiTurnGemini(
        baseURL: URL,
        model: String,
        apiKey: String,
        additionalHeaders: [String: String],
        messages: [AgentMessage],
        tools: [LLMAgentTool],
        config: LLMCallConfig
    ) async throws -> AgentTurnResult {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("models/\(model):generateContent"),
            resolvingAgainstBaseURL: false
        ) else {
            throw AgentError.llmConnectionFailed(reason: "Invalid Gemini endpoint.")
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw AgentError.llmConnectionFailed(reason: "Invalid Gemini endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        AgentRequestConfiguration.apply(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        var generationConfig: [String: Any] = [
            "candidateCount": 1,
            "maxOutputTokens": 4096
        ]
        if let temp = config.temperature {
            generationConfig["temperature"] = temp
        }
        OpenAICompatibleResponseSupport.applyGeminiTuning(generationConfig: &generationConfig, model: model)

        var body: [String: Any] = [
            "contents": AgentMessage.toGeminiContents(messages),
            "generationConfig": generationConfig,
            "tools": [
                [
                    "functionDeclarations": tools.map { tool in
                        [
                            "name": tool.name,
                            "description": tool.description,
                            "parameters": tool.inputSchema.jsonObject
                        ] as [String: Any]
                    }
                ]
            ]
        ]

        if let systemInstruction = AgentMessage.extractGeminiSystemInstruction(messages) {
            body["systemInstruction"] = systemInstruction
        }

        if let forcedTool = config.forcedToolName {
            body["toolConfig"] = [
                "functionCallingConfig": [
                    "mode": "ANY",
                    "allowedFunctionNames": [forcedTool]
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await RemoteLLMClient.performJSONRequest(request)
        return parseGeminiTurnResult(from: data)
    }

    func parseGeminiTurnResult(from data: Data) -> AgentTurnResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            return AgentTurnResult(turn: .text(""), tokenUsage: nil)
        }

        var text = ""
        var toolCalls: [AgentToolCall] = []

        for part in parts {
            if let textContent = part["text"] as? String {
                text += textContent
            } else if let functionCall = part["functionCall"] as? [String: Any],
                      let name = functionCall["name"] as? String {
                let args = functionCall["args"] ?? [:]
                let argsJSON: String = if JSONSerialization.isValidJSONObject(args),
                                          let argsData = try? JSONSerialization.data(withJSONObject: args),
                                          let str = String(data: argsData, encoding: .utf8) {
                    str
                } else {
                    "{}"
                }
                let id = "\(name)_\(UUID().uuidString.prefix(8))"
                toolCalls.append(AgentToolCall(id: id, name: name, argumentsJSON: argsJSON))
            }
        }

        let tokenUsage = parseGeminiTokenUsage(from: object)

        let turn: AgentTurn = if toolCalls.isEmpty {
            .text(text)
        } else if text.isEmpty {
            .toolCalls(toolCalls)
        } else {
            .textWithToolCalls(text: text, toolCalls: toolCalls)
        }

        return AgentTurnResult(turn: turn, tokenUsage: tokenUsage)
    }

    /// Legacy helper kept for backward compatibility with tests.
    func parseGeminiTurn(from data: Data) -> AgentTurn {
        parseGeminiTurnResult(from: data).turn
    }

    private func parseGeminiTokenUsage(from object: [String: Any]) -> LLMTokenUsage? {
        guard let meta = object["usageMetadata"] as? [String: Any] else { return nil }
        let promptTokens = meta["promptTokenCount"] as? Int ?? 0
        let completionTokens = meta["candidatesTokenCount"] as? Int ?? 0
        let totalTokens = meta["totalTokenCount"] as? Int ?? (promptTokens + completionTokens)
        guard totalTokens > 0 else { return nil }
        return LLMTokenUsage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens
        )
    }
}
