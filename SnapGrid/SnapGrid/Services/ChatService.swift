import AppKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class ChatService {
    var messages: [ChatMessage] = []
    var isProcessing: Bool = false

    private let maxToolIterations = 10

    // Read user's selected provider and model from AppStorage-backed UserDefaults
    private var provider: AIProvider {
        let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? AIProvider.openai.rawValue
        return AIProvider(rawValue: raw) ?? .openai
    }

    private var modelId: String {
        let key = "\(provider.rawValue)Model"
        let stored = UserDefaults.standard.string(forKey: key) ?? ModelDiscoveryService.autoModelValue
        return stored == ModelDiscoveryService.autoModelValue ? provider.defaultModel : stored
    }

    // MARK: - Public API

    func sendMessage(_ text: String, context: ChatContext) {
        let userMessage = ChatMessage(role: .user, content: [.text(text)])
        messages.append(userMessage)
        isProcessing = true

        Task {
            await runAgentLoop(userText: text, context: context)
            isProcessing = false
        }
    }

    func clearConversation() {
        messages.removeAll()
    }

    // MARK: - Agent Loop

    private func runAgentLoop(userText: String, context: ChatContext) async {
        guard let apiKey = try? KeychainService.get(service: provider.keychainService), !apiKey.isEmpty else {
            messages.append(ChatMessage(role: .assistant, content: [.error("No API key configured. Please add one in Settings.")]))
            return
        }

        // Build conversation history for the API
        var apiMessages = buildAPIMessages()

        // Collect images from tool calls — they'll be embedded in the final text reply
        var collectedImages: [(id: String, image: NSImage)] = []

        for _ in 0..<maxToolIterations {
            do {
                let response = try await callProvider(
                    apiKey: apiKey,
                    model: modelId,
                    messages: apiMessages
                )

                switch response {
                case .text(let text):
                    // Parse ![image](ID) markers and interleave text with images
                    let content = parseInlineImages(text: text, collectedImages: collectedImages)
                    messages.append(ChatMessage(role: .assistant, content: content))
                    return

                case .toolCalls(let calls):
                    // Show tool call status in UI
                    var assistantContent: [ChatContent] = []
                    for call in calls {
                        assistantContent.append(.toolCall(id: call.id, name: call.name, status: .running))
                    }
                    let assistantIndex = messages.count
                    messages.append(ChatMessage(role: .assistant, content: assistantContent))

                    // Append assistant message with tool calls to API history
                    appendAssistantToolCallMessage(calls, to: &apiMessages)

                    // Execute each tool and collect results
                    for (i, call) in calls.enumerated() {
                        let result = await ChatToolExecutor.execute(
                            toolName: call.name,
                            arguments: call.arguments,
                            context: context
                        )

                        // Update tool call status in UI
                        messages[assistantIndex].content[i] = .toolCall(id: call.id, name: call.name, status: .completed)

                        // Collect images for the final reply
                        collectedImages.append(contentsOf: result.images)

                        // Append tool result to API messages
                        appendToolResultMessage(
                            call: call,
                            result: result,
                            to: &apiMessages
                        )
                    }
                    // Loop continues — re-send with tool results

                case .textAndToolCalls(let text, let calls):
                    // Some providers (Anthropic) can return text + tool calls together
                    var assistantContent: [ChatContent] = [.text(text)]
                    for call in calls {
                        assistantContent.append(.toolCall(id: call.id, name: call.name, status: .running))
                    }
                    let assistantIndex = messages.count
                    messages.append(ChatMessage(role: .assistant, content: assistantContent))

                    appendAssistantToolCallMessage(calls, to: &apiMessages, prefixText: text)

                    for (callIndex, call) in calls.enumerated() {
                        let result = await ChatToolExecutor.execute(
                            toolName: call.name,
                            arguments: call.arguments,
                            context: context
                        )

                        // +1 offset for the text content at index 0
                        messages[assistantIndex].content[callIndex + 1] = .toolCall(id: call.id, name: call.name, status: .completed)

                        // Collect images for the final reply
                        collectedImages.append(contentsOf: result.images)

                        appendToolResultMessage(call: call, result: result, to: &apiMessages)
                    }
                }
            } catch {
                messages.append(ChatMessage(role: .assistant, content: [.error(error.localizedDescription)]))
                return
            }
        }

        messages.append(ChatMessage(role: .assistant, content: [.error("Reached maximum tool iterations. Please try a simpler question.")]))
    }

    // MARK: - API Message Building

    private let systemPrompt = """
    You are a helpful AI assistant for SnapGrid, an image library app. You help users explore, find, and understand their image collection.

    You have access to the following tools:
    - search_library: Search images by keywords matching pattern tags, descriptions, and summaries
    - get_image: Retrieve a specific image to view it and see its metadata
    - analyze_image: Perform custom visual analysis on an image (you'll see the image via vision)

    IMPORTANT — Embedding images in your replies:
    After using search_library or get_image, you can embed images inline in your response using this syntax: ![image](MEDIA_ITEM_ID)
    The app will replace these with actual image thumbnails. Use this to show users the images you're talking about, placed exactly where they're relevant in your text.

    Example response after a search:
    "I found 3 dashboard screenshots. Here's the most relevant one:

    ![image](abc-123-def)

    This design uses a sidebar navigation pattern with a card-based content area."

    Guidelines:
    - When users ask to find images, use search_library first
    - When users ask about a specific image, use get_image to retrieve it
    - When users ask detailed visual questions about an image, use analyze_image
    - ALWAYS embed images in your reply using ![image](ID) when you have relevant results — don't just describe them
    - Place images at natural points in your explanation so users can see what you're describing
    - Be concise but helpful in your responses
    - When showing search results, summarize what you found and embed the most relevant images
    - If search returns no results, suggest alternative search terms
    """

    private func buildAPIMessages() -> [APIMessage] {
        var apiMsgs: [APIMessage] = []

        for msg in messages {
            switch msg.role {
            case .user:
                let text = msg.content.compactMap { content -> String? in
                    if case .text(let t) = content { return t }
                    return nil
                }.joined(separator: "\n")
                apiMsgs.append(.user(text))

            case .assistant:
                let text = msg.content.compactMap { content -> String? in
                    if case .text(let t) = content { return t }
                    return nil
                }.joined(separator: "\n")
                if !text.isEmpty {
                    apiMsgs.append(.assistant(text))
                }
            }
        }

        return apiMsgs
    }

    private func appendAssistantToolCallMessage(_ calls: [ToolCallInfo], to messages: inout [APIMessage], prefixText: String? = nil) {
        messages.append(.assistantToolCall(text: prefixText, toolCalls: calls))
    }

    private func appendToolResultMessage(call: ToolCallInfo, result: ChatToolExecutor.ToolResult, to messages: inout [APIMessage]) {
        messages.append(.toolResult(toolCallId: call.id, name: call.name, content: result.textContent, base64Image: result.base64Image))
    }

    // MARK: - Provider Dispatch

    private enum ChatResponse {
        case text(String)
        case toolCalls([ToolCallInfo])
        case textAndToolCalls(String, [ToolCallInfo])
    }

    struct ToolCallInfo {
        let id: String
        let name: String
        let arguments: [String: Any]
    }

    /// Intermediate representation for API messages
    enum APIMessage {
        case user(String)
        case assistant(String)
        case assistantToolCall(text: String?, toolCalls: [ToolCallInfo])
        case toolResult(toolCallId: String, name: String, content: String, base64Image: String?)
    }

    private func callProvider(apiKey: String, model: String, messages: [APIMessage]) async throws -> ChatResponse {
        switch provider {
        case .openai:
            return try await callOpenAI(apiKey: apiKey, model: model, messages: messages)
        case .anthropic:
            return try await callAnthropic(apiKey: apiKey, model: model, messages: messages)
        case .gemini:
            return try await callGemini(apiKey: apiKey, model: model, messages: messages)
        case .openrouter:
            return try await callOpenRouter(apiKey: apiKey, model: model, messages: messages)
        }
    }

    // MARK: - OpenAI

    private func callOpenAI(apiKey: String, model: String, messages: [APIMessage]) async throws -> ChatResponse {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": openAIMessages(messages),
            "tools": ChatTool.openAITools(),
            "max_completion_tokens": 4096,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        return try parseOpenAIResponse(data)
    }

    private func openAIMessages(_ messages: [APIMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for msg in messages {
            switch msg {
            case .user(let text):
                result.append(["role": "user", "content": text])

            case .assistant(let text):
                result.append(["role": "assistant", "content": text])

            case .assistantToolCall(let text, let toolCalls):
                var msg: [String: Any] = ["role": "assistant"]
                if let text { msg["content"] = text }
                msg["tool_calls"] = toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": jsonString(call.arguments),
                        ] as [String: Any],
                    ] as [String: Any]
                }
                result.append(msg)

            case .toolResult(let toolCallId, _, let content, let base64Image):
                if let base64 = base64Image {
                    // Send image as part of the tool result for vision
                    result.append([
                        "role": "tool",
                        "tool_call_id": toolCallId,
                        "content": [
                            ["type": "text", "text": content],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
                        ] as [[String: Any]],
                    ])
                } else {
                    result.append([
                        "role": "tool",
                        "tool_call_id": toolCallId,
                        "content": content,
                    ])
                }
            }
        }

        return result
    }

    private func parseOpenAIResponse(_ data: Data) throws -> ChatResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        guard let message = choices?.first?["message"] as? [String: Any] else {
            throw ChatError.invalidResponse
        }

        let textContent = message["content"] as? String
        let toolCalls = message["tool_calls"] as? [[String: Any]]

        if let toolCalls, !toolCalls.isEmpty {
            let calls = toolCalls.compactMap { parseOpenAIToolCall($0) }
            if let text = textContent, !text.isEmpty {
                return .textAndToolCalls(text, calls)
            }
            return .toolCalls(calls)
        }

        return .text(textContent ?? "")
    }

    private func parseOpenAIToolCall(_ dict: [String: Any]) -> ToolCallInfo? {
        guard let id = dict["id"] as? String,
              let function = dict["function"] as? [String: Any],
              let name = function["name"] as? String else { return nil }
        let argsString = function["arguments"] as? String ?? "{}"
        let arguments = parseJSON(argsString)
        return ToolCallInfo(id: id, name: name, arguments: arguments)
    }

    // MARK: - Anthropic

    private func callAnthropic(apiKey: String, model: String, messages: [APIMessage]) async throws -> ChatResponse {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": anthropicMessages(messages),
            "tools": ChatTool.anthropicTools(),
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        return try parseAnthropicResponse(data)
    }

    private func anthropicMessages(_ messages: [APIMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        for msg in messages {
            switch msg {
            case .user(let text):
                result.append(["role": "user", "content": text])

            case .assistant(let text):
                result.append(["role": "assistant", "content": [["type": "text", "text": text]]])

            case .assistantToolCall(let text, let toolCalls):
                var content: [[String: Any]] = []
                if let text { content.append(["type": "text", "text": text]) }
                for call in toolCalls {
                    content.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": call.arguments,
                    ])
                }
                result.append(["role": "assistant", "content": content])

            case .toolResult(let toolCallId, _, let contentText, let base64Image):
                var content: [[String: Any]] = []

                var toolResult: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": toolCallId,
                ]

                if let base64 = base64Image {
                    toolResult["content"] = [
                        ["type": "text", "text": contentText],
                        ["type": "image", "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64,
                        ]],
                    ] as [[String: Any]]
                } else {
                    toolResult["content"] = contentText
                }
                content.append(toolResult)
                result.append(["role": "user", "content": content])
            }
        }

        return result
    }

    private func parseAnthropicResponse(_ data: Data) throws -> ChatResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]] else {
            throw ChatError.invalidResponse
        }

        var textParts: [String] = []
        var toolCalls: [ToolCallInfo] = []

        for block in content {
            if let type = block["type"] as? String {
                if type == "text", let text = block["text"] as? String {
                    textParts.append(text)
                } else if type == "tool_use",
                          let id = block["id"] as? String,
                          let name = block["name"] as? String,
                          let input = block["input"] as? [String: Any] {
                    toolCalls.append(ToolCallInfo(id: id, name: name, arguments: input))
                }
            }
        }

        let text = textParts.joined(separator: "\n")

        if !toolCalls.isEmpty {
            if !text.isEmpty {
                return .textAndToolCalls(text, toolCalls)
            }
            return .toolCalls(toolCalls)
        }

        return .text(text)
    }

    // MARK: - Gemini

    private func callGemini(apiKey: String, model: String, messages: [APIMessage]) async throws -> ChatResponse {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": geminiMessages(messages),
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "tools": ChatTool.geminiTools(),
            "generationConfig": ["maxOutputTokens": 4096],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        return try parseGeminiResponse(data)
    }

    private func geminiMessages(_ messages: [APIMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        for msg in messages {
            switch msg {
            case .user(let text):
                result.append(["role": "user", "parts": [["text": text]]])

            case .assistant(let text):
                result.append(["role": "model", "parts": [["text": text]]])

            case .assistantToolCall(let text, let toolCalls):
                var parts: [[String: Any]] = []
                if let text { parts.append(["text": text]) }
                for call in toolCalls {
                    parts.append(["functionCall": ["name": call.name, "args": call.arguments]])
                }
                result.append(["role": "model", "parts": parts])

            case .toolResult(_, let name, let content, let base64Image):
                var parts: [[String: Any]] = [
                    ["functionResponse": [
                        "name": name,
                        "response": ["result": content],
                    ] as [String: Any]]
                ]
                if let base64 = base64Image {
                    parts.append(["inlineData": ["mimeType": "image/jpeg", "data": base64]])
                }
                result.append(["role": "user", "parts": parts])
            }
        }

        return result
    }

    private func parseGeminiResponse(_ data: Data) throws -> ChatResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        guard let parts = content?["parts"] as? [[String: Any]] else {
            throw ChatError.invalidResponse
        }

        var textParts: [String] = []
        var toolCalls: [ToolCallInfo] = []

        for part in parts {
            if let text = part["text"] as? String {
                textParts.append(text)
            } else if let fc = part["functionCall"] as? [String: Any],
                      let name = fc["name"] as? String {
                let args = fc["args"] as? [String: Any] ?? [:]
                // Gemini doesn't provide IDs, generate one
                toolCalls.append(ToolCallInfo(id: UUID().uuidString, name: name, arguments: args))
            }
        }

        let text = textParts.joined(separator: "\n")

        if !toolCalls.isEmpty {
            if !text.isEmpty { return .textAndToolCalls(text, toolCalls) }
            return .toolCalls(toolCalls)
        }

        return .text(text)
    }

    // MARK: - OpenRouter

    private func callOpenRouter(apiKey: String, model: String, messages: [APIMessage]) async throws -> ChatResponse {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://snapgrid.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("SnapGrid", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": openAIMessages(messages), // OpenRouter uses OpenAI format
            "tools": ChatTool.openAITools(),
            "max_tokens": 4096,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        return try parseOpenAIResponse(data) // Same response format as OpenAI
    }

    // MARK: - Inline Image Parsing

    /// Parses `![image](MEDIA_ITEM_ID)` markers in the LLM's text response
    /// and produces interleaved text + image content blocks.
    private func parseInlineImages(text: String, collectedImages: [(id: String, image: NSImage)]) -> [ChatContent] {
        let imageMap = Dictionary(collectedImages.map { ($0.id, $0.image) }, uniquingKeysWith: { first, _ in first })

        // Regex for ![image](ID) — ID captured in group 1
        let pattern = #"!\[image\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(text)]
        }

        var content: [ChatContent] = []
        var lastEnd = text.startIndex

        let nsRange = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let idRange = Range(match.range(at: 1), in: text) else { return }

            // Text before this marker
            let before = String(text[lastEnd..<fullRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                content.append(.text(before))
            }

            // The image
            let mediaId = String(text[idRange])
            if let thumbnail = imageMap[mediaId] {
                content.append(.image(mediaItemId: mediaId, thumbnail: thumbnail))
            }

            lastEnd = fullRange.upperBound
        }

        // Remaining text after last marker
        let remaining = String(text[lastEnd...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            content.append(.text(remaining))
        }

        // Fallback: if no markers were found, return the full text
        if content.isEmpty {
            content.append(.text(text))
        }

        return content
    }

    // MARK: - Helpers

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatError.apiError(statusCode: httpResponse.statusCode, message: body)
        }
    }

    private func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func parseJSON(_ string: String) -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    enum ChatError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured"
            case .invalidResponse: return "Invalid response from AI provider"
            case .apiError(let code, let msg):
                // Try to extract a user-friendly message from API error JSON
                if let data = msg.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return message
                }
                return "API error (\(code)): \(msg.prefix(200))"
            }
        }
    }
}
