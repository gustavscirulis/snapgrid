import Foundation

// MARK: - Tool Definitions

/// Provider-agnostic tool definitions for the AI assistant.
/// Each tool defines its name, description, and parameters, plus
/// methods to serialize to each provider's JSON schema format.
enum ChatTool {
    struct Definition {
        let name: String
        let description: String
        let parameters: [Parameter]
    }

    struct Parameter {
        let name: String
        let type: String  // "string", "integer", etc.
        let description: String
        let required: Bool
        let enumValues: [String]?

        init(name: String, type: String, description: String, required: Bool = true, enumValues: [String]? = nil) {
            self.name = name
            self.type = type
            self.description = description
            self.required = required
            self.enumValues = enumValues
        }
    }

    // MARK: - Tool Definitions

    static let searchLibrary = Definition(
        name: "search_library",
        description: "Search the user's image library by keyword. Matches against AI-generated pattern tags, image descriptions, and summaries. Returns matching items with their metadata. Use this when the user asks to find, show, or look for images.",
        parameters: [
            Parameter(name: "query", type: "string", description: "Search query — matches against pattern names, image descriptions, and summaries"),
            Parameter(name: "space_id", type: "string", description: "Optional space ID to limit search to a specific space. Omit to search all spaces.", required: false),
        ]
    )

    static let getImage = Definition(
        name: "get_image",
        description: "Retrieve a specific image by its ID to display in the conversation and optionally analyze it. Use this after search_library to show the user specific images, or when you need to look at an image to answer a question about it.",
        parameters: [
            Parameter(name: "media_item_id", type: "string", description: "The ID of the media item to retrieve"),
        ]
    )

    static let analyzeImage = Definition(
        name: "analyze_image",
        description: "Perform custom visual analysis on a specific image using AI vision. Use this when the user asks a specific question about an image's content, style, colors, layout, or other visual properties that require looking at the image.",
        parameters: [
            Parameter(name: "media_item_id", type: "string", description: "The ID of the media item to analyze"),
            Parameter(name: "question", type: "string", description: "The specific question to answer about the image"),
        ]
    )

    static let allTools: [Definition] = [searchLibrary, getImage, analyzeImage]

    // MARK: - Provider Serialization

    /// JSON Schema for parameters (shared across providers)
    static func jsonSchema(for tool: Definition) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in tool.parameters {
            var prop: [String: Any] = [
                "type": param.type,
                "description": param.description,
            ]
            if let enums = param.enumValues {
                prop["enum"] = enums
            }
            properties[param.name] = prop
            if param.required { required.append(param.name) }
        }

        return [
            "type": "object",
            "properties": properties,
            "required": required,
        ]
    }

    /// OpenAI / OpenRouter format
    static func openAITools() -> [[String: Any]] {
        allTools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": jsonSchema(for: tool),
                ] as [String: Any],
            ]
        }
    }

    /// Anthropic format
    static func anthropicTools() -> [[String: Any]] {
        allTools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": jsonSchema(for: tool),
            ]
        }
    }

    /// Gemini format
    static func geminiTools() -> [[String: Any]] {
        [
            [
                "functionDeclarations": allTools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": jsonSchema(for: tool),
                    ] as [String: Any]
                }
            ]
        ]
    }
}
