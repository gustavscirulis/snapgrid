import AppKit
import Foundation
import SwiftData

/// Context passed to tools so they can access the app's data layer.
@MainActor
struct ChatContext {
    let modelContext: ModelContext
    let activeSpaceId: String?
    let allItems: [MediaItem]
    let spaces: [Space]
}

/// Executes tool calls against local data.
/// All methods are MainActor because they access SwiftData and image caches.
@MainActor
enum ChatToolExecutor {

    struct ToolResult {
        let textContent: String          // JSON or text to send back to the LLM
        var images: [(id: String, image: NSImage)] = []  // Images to display inline in chat
        var base64Image: String?         // For vision follow-up (analyze_image)
    }

    static func execute(
        toolName: String,
        arguments: [String: Any],
        context: ChatContext
    ) async -> ToolResult {
        switch toolName {
        case "search_library":
            let query = arguments["query"] as? String ?? ""
            let spaceId = arguments["space_id"] as? String
            return searchLibrary(query: query, spaceId: spaceId, context: context)

        case "get_image":
            let mediaItemId = arguments["media_item_id"] as? String ?? ""
            return await getImage(mediaItemId: mediaItemId, context: context)

        case "analyze_image":
            let mediaItemId = arguments["media_item_id"] as? String ?? ""
            let question = arguments["question"] as? String ?? ""
            return await analyzeImage(mediaItemId: mediaItemId, question: question, context: context)

        default:
            return ToolResult(textContent: "{\"error\": \"Unknown tool: \(toolName)\"}")
        }
    }

    // MARK: - search_library

    private static func searchLibrary(query: String, spaceId: String?, context: ChatContext) -> ToolResult {
        var items = context.allItems

        // Filter by space if specified
        if let spaceId {
            items = items.filter { $0.space?.id == spaceId }
        } else if let activeSpaceId = context.activeSpaceId {
            // Default to current space context
            items = items.filter { $0.space?.id == activeSpaceId }
        }

        // Search — same logic as ContentView.itemsForSpace
        if !query.isEmpty {
            let q = query.lowercased()
            items = items.filter { item in
                if let patterns = item.analysisResult?.patterns,
                   patterns.contains(where: { $0.name.lowercased().contains(q) }) {
                    return true
                }
                if let ctx = item.analysisResult?.imageContext.lowercased(), ctx.contains(q) {
                    return true
                }
                if let summary = item.analysisResult?.imageSummary.lowercased(), summary.contains(q) {
                    return true
                }
                if q == "video" && item.isVideo { return true }
                if q == "image" && !item.isVideo { return true }
                return false
            }
        }

        // Cap results
        let capped = Array(items.prefix(20))

        // Build JSON response
        let results: [[String: Any]] = capped.map { item in
            var dict: [String: Any] = [
                "id": item.id,
                "filename": item.filename,
                "type": item.mediaType.rawValue,
                "width": item.width,
                "height": item.height,
            ]
            if let result = item.analysisResult {
                dict["summary"] = result.imageSummary
                dict["context"] = result.imageContext
                dict["patterns"] = result.patterns.map { $0.name }
            }
            if let space = item.space {
                dict["space"] = space.name
            }
            return dict
        }

        let response: [String: Any] = [
            "total_matches": items.count,
            "showing": capped.count,
            "items": results,
        ]

        let jsonData = (try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        // Load thumbnails for inline display
        var images: [(id: String, image: NSImage)] = []
        for item in capped {
            if let thumb = loadThumbnail(for: item) {
                images.append((id: item.id, image: thumb))
            }
        }

        return ToolResult(textContent: jsonString, images: images)
    }

    // MARK: - get_image

    private static func getImage(mediaItemId: String, context: ChatContext) async -> ToolResult {
        guard let item = context.allItems.first(where: { $0.id == mediaItemId }) else {
            return ToolResult(textContent: "{\"error\": \"Image not found with ID: \(mediaItemId)\"}")
        }

        // Load thumbnail for inline display
        let thumbnail = loadThumbnail(for: item)

        // Load full image and convert to base64 for the LLM to see
        let base64 = loadBase64(for: item)

        var info: [String: Any] = [
            "id": item.id,
            "filename": item.filename,
            "type": item.mediaType.rawValue,
            "width": item.width,
            "height": item.height,
        ]
        if let result = item.analysisResult {
            info["summary"] = result.imageSummary
            info["context"] = result.imageContext
            info["patterns"] = result.patterns.map { "\($0.name) (\(Int($0.confidence * 100))%)" }
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        var result = ToolResult(textContent: jsonString)
        if let thumbnail {
            result.images = [(id: item.id, image: thumbnail)]
        }
        result.base64Image = base64
        return result
    }

    // MARK: - analyze_image

    private static func analyzeImage(mediaItemId: String, question: String, context: ChatContext) async -> ToolResult {
        guard let item = context.allItems.first(where: { $0.id == mediaItemId }) else {
            return ToolResult(textContent: "{\"error\": \"Image not found with ID: \(mediaItemId)\"}")
        }

        // Load thumbnail for display
        let thumbnail = loadThumbnail(for: item)

        // Load full image for analysis
        let mediaURL = MediaStorageService.shared.mediaURL(filename: item.filename)
        guard let fullImage = NSImage(contentsOf: mediaURL),
              let base64 = AIAnalysisService.imageToBase64(fullImage) else {
            return ToolResult(textContent: "{\"error\": \"Could not load image for analysis\"}")
        }

        var result = ToolResult(textContent: "{\"analysis_ready\": true, \"question\": \"\(question)\", \"media_item_id\": \"\(mediaItemId)\"}")
        if let thumbnail {
            result.images = [(id: item.id, image: thumbnail)]
        }
        result.base64Image = base64
        return result
    }

    // MARK: - Helpers

    private static func loadThumbnail(for item: MediaItem) -> NSImage? {
        // Try cache first
        if let cached = ImageCacheService.shared.image(forKey: item.id) {
            return cached
        }
        // Load from disk
        let thumbURL = MediaStorageService.shared.thumbnailURL(id: item.id)
        if let image = NSImage(contentsOf: thumbURL) {
            ImageCacheService.shared.setImage(image, forKey: item.id)
            return image
        }
        return nil
    }

    private static func loadBase64(for item: MediaItem) -> String? {
        let mediaURL = MediaStorageService.shared.mediaURL(filename: item.filename)
        guard let image = NSImage(contentsOf: mediaURL) else { return nil }
        return AIAnalysisService.imageToBase64(image)
    }
}
