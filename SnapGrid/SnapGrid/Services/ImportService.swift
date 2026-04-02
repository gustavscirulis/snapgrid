import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@Observable
@MainActor
final class ImportService {

    private let storage = MediaStorageService.shared
    private let analysisService = AIAnalysisService.shared
    private let sidecarService = MetadataSidecarService.shared

    private let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]
    private let videoTypes: Set<String> = ["mp4", "webm", "mov", "avi", "m4v"]

    func importFiles(_ urls: [URL], into context: ModelContext, spaceId: String? = nil) async {
        for url in urls {
            do {
                try await importSingleFile(url, into: context, spaceId: spaceId)
            } catch {
                print("[ImportService] Failed to import \(url.lastPathComponent): \(error)")
            }
        }
    }

    /// Import a raw NSImage (e.g. from pasteboard or browser drag) — converts to PNG and runs the full pipeline.
    func importImage(_ image: NSImage, into context: ModelContext, spaceId: String? = nil) async {
        do {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw ImportError.cannotReadDimensions
            }

            guard let pixelSize = image.pixelSize else {
                throw ImportError.cannotReadDimensions
            }

            let id = UUID().uuidString
            let filename = "\(id).png"
            let width = Int(pixelSize.width)
            let height = Int(pixelSize.height)

            _ = try storage.saveMedia(data: pngData, filename: filename)
            _ = try ThumbnailService.generateThumbnail(from: image, id: id)

            let item = MediaItem(id: id, mediaType: .image, filename: filename, width: width, height: height)

            if let spaceId {
                let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
                if let space = try? context.fetch(descriptor).first {
                    item.space = space
                }
            }

            context.insert(item)
            try context.save()
            sidecarService.writeSidecar(for: item)

            Task { @MainActor [weak self] in
                await self?.analyzeItem(item, context: context)
            }
        } catch {
            print("[ImportService] Failed to import pasted image: \(error)")
        }
    }

    private func importSingleFile(_ url: URL, into context: ModelContext, spaceId: String?, sourceURL: String? = nil) async throws {
        let ext = url.pathExtension.lowercased()
        let isVideo = videoTypes.contains(ext)
        let isImage = imageTypes.contains(ext)

        guard isVideo || isImage else {
            throw ImportError.unsupportedFileType(ext)
        }

        let id = UUID().uuidString
        let mediaType: MediaType = isVideo ? .video : .image
        let targetExt = isVideo ? "mp4" : "png"
        let filename = "\(id).\(targetExt)"

        // Get dimensions
        var width: Int
        var height: Int
        var duration: Double?

        if isVideo {
            let info = try await VideoFrameExtractor.getVideoInfo(from: url)
            width = info.width
            height = info.height
            duration = info.duration
        } else {
            guard let image = NSImage(contentsOf: url), let pixelSize = image.pixelSize else {
                throw ImportError.cannotReadDimensions
            }
            width = Int(pixelSize.width)
            height = Int(pixelSize.height)
        }

        // Copy file to media storage
        _ = try storage.copyMedia(from: url, filename: filename)

        // Generate thumbnail
        if isVideo {
            if let posterFrame = try? await VideoFrameExtractor.extractPosterFrame(from: storage.mediaURL(filename: filename)) {
                // Use poster frame pixel dimensions as authoritative —
                // they reflect the true display aspect ratio (handles PAR, rotation)
                if let pixelSize = posterFrame.pixelSize, Int(pixelSize.width) > 0, Int(pixelSize.height) > 0 {
                    width = Int(pixelSize.width)
                    height = Int(pixelSize.height)
                }
                _ = try? ThumbnailService.generateThumbnail(from: posterFrame, id: id)
            }
        } else {
            _ = try? await ThumbnailService.generateThumbnail(from: storage.mediaURL(filename: filename), id: id)
        }

        // Create SwiftData model
        let item = MediaItem(id: id, mediaType: mediaType, filename: filename, width: width, height: height, duration: duration)

        // Assign to space if specified
        if let spaceId {
            let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
            if let space = try? context.fetch(descriptor).first {
                item.space = space
            }
        }

        context.insert(item)

        // Set sourceURL after insert so SwiftData tracks the property change
        item.sourceURL = sourceURL

        try context.save()
        sidecarService.writeSidecar(for: item)

        // Queue AI analysis in background
        Task { @MainActor [weak self] in
            await self?.analyzeItem(item, context: context)
        }
    }

    func analyzeItem(_ item: MediaItem, context: ModelContext) async {
        // Prevent duplicate analysis (e.g. SyncWatcher detecting our own sidecar write)
        guard !item.isAnalyzing else {
            print("[Analysis] Skipping \(item.id) — already analyzing")
            return
        }

        // Check for API key
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "openai") ?? .openai
        guard KeychainService.exists(service: provider.keychainService) else {
            print("[Analysis] No API key for \(provider.rawValue), skipping")
            return
        }

        let storedModel = UserDefaults.standard.string(forKey: "\(provider.rawValue)Model") ?? ModelDiscoveryService.autoModelValue
        let model: String
        if storedModel == ModelDiscoveryService.autoModelValue {
            model = await ModelDiscoveryService.shared.resolveAutoModel(for: provider)
        } else {
            model = storedModel
        }
        print("[Analysis] Starting analysis with \(provider.rawValue)/\(model) for \(item.id)")

        item.isAnalyzing = true
        try? context.save()

        do {
            let result: AnalysisResult
            let storage = self.storage

            // Resolve guidance and space context separately
            var guidance: String?
            var spaceContext: String?

            if let space = item.space {
                spaceContext = "This image belongs to a collection called \"\(space.name)\". Use this as context to inform your analysis."
                if space.useCustomPrompt, let custom = space.customPrompt, !custom.isEmpty {
                    guidance = custom
                }
            }
            if guidance == nil, UserDefaults.standard.bool(forKey: "useAllSpacePrompt") {
                let allGuidance = UserDefaults.standard.string(forKey: "allSpacePrompt") ?? ""
                if !allGuidance.isEmpty {
                    guidance = allGuidance
                }
            }

            if item.isVideo {
                let frames = try await VideoFrameExtractor.extractAnalysisFrames(from: storage.mediaURL(filename: item.filename))
                result = try await analysisService.analyzeVideo(frames: frames, provider: provider, model: model, guidance: guidance, spaceContext: spaceContext)
            } else {
                guard let image = NSImage(contentsOf: storage.mediaURL(filename: item.filename)) else {
                    throw ImportError.cannotReadDimensions
                }
                result = try await analysisService.analyze(image: image, provider: provider, model: model, guidance: guidance, spaceContext: spaceContext)
            }

            print("[Analysis] Success for \(item.id): \(result.patterns.count) patterns")
            item.analysisResult = result
            item.isAnalyzing = false
            item.analysisError = nil
            try? context.save()
            sidecarService.writeSidecar(for: item)
            NotificationCenter.default.post(name: .analysisCompleted, object: nil, userInfo: ["itemId": item.id])
        } catch {
            print("[Analysis] Failed for \(item.id): \(error)")
            item.isAnalyzing = false
            item.analysisError = error.localizedDescription
            try? context.save()
        }
    }

    func analyzeUnanalyzedItems(from items: [MediaItem], context: ModelContext) async {
        let unanalyzed = items.filter { $0.analysisResult == nil && $0.analysisError == nil && !$0.isAnalyzing }
        guard !unanalyzed.isEmpty else { return }

        print("[Analysis] Batch analyzing \(unanalyzed.count) unanalyzed items")
        for item in unanalyzed {
            await analyzeItem(item, context: context)
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// Import media from an X / Twitter post URL — resolves the tweet to a direct
    /// MP4 or image link and runs it through the standard URL import pipeline.
    func importFromTwitterURL(_ url: URL, into context: ModelContext, spaceId: String? = nil) async throws {
        let result = try await TwitterVideoService.extractMediaURL(from: url)
        switch result {
        case .video(let mediaURL), .image(let mediaURL):
            try await importFromURL(mediaURL, into: context, spaceId: spaceId, sourceURL: url.absoluteString)
        }
    }

    /// Import media from a remote HTTP/HTTPS URL — downloads the file, determines its type,
    /// and runs it through the standard import pipeline.
    func importFromURL(_ url: URL, into context: ModelContext, spaceId: String? = nil, sourceURL: String? = nil) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ImportError.downloadFailed(code)
        }

        let ext = Self.fileExtension(
            from: httpResponse.value(forHTTPHeaderField: "Content-Type"),
            urlPathExtension: url.pathExtension.lowercased()
        )

        guard let ext, (imageTypes.contains(ext) || videoTypes.contains(ext)) else {
            throw ImportError.unsupportedFileType(ext ?? "unknown")
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try await importSingleFile(tempFile, into: context, spaceId: spaceId, sourceURL: sourceURL)
    }

    /// Map a Content-Type MIME string to a file extension. Falls back to URL path extension.
    private static func fileExtension(from contentType: String?, urlPathExtension: String?) -> String? {
        if let mime = contentType?.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) {
            let mimeMap: [String: String] = [
                "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg",
                "image/gif": "gif", "image/webp": "webp", "image/bmp": "bmp",
                "image/tiff": "tiff", "image/heic": "heic",
                "video/mp4": "mp4", "video/webm": "webm",
                "video/quicktime": "mov", "video/x-msvideo": "avi", "video/x-m4v": "m4v",
            ]
            if let ext = mimeMap[mime] { return ext }
        }

        let allKnown: Set<String> = ["png","jpg","jpeg","gif","bmp","tiff","webp","heic",
                                      "mp4","webm","mov","avi","m4v"]
        if let ext = urlPathExtension, allKnown.contains(ext) { return ext }
        return nil
    }

    enum ImportError: LocalizedError {
        case unsupportedFileType(String)
        case cannotReadDimensions
        case downloadFailed(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let ext): return "Unsupported file type: .\(ext)"
            case .cannotReadDimensions: return "Cannot read image dimensions"
            case .downloadFailed(let code): return "Download failed (HTTP \(code))"
            }
        }
    }
}
