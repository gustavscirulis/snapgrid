import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@Observable
@MainActor
final class ImportService {

    private let storage = MediaStorageService.shared
    private let analysisService = AIAnalysisService.shared

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

    private func importSingleFile(_ url: URL, into context: ModelContext, spaceId: String?) async throws {
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
        let width: Int
        let height: Int
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
        try context.save()

        // Queue AI analysis in background
        Task { @MainActor [weak self] in
            await self?.analyzeItem(item, context: context)
        }
    }

    func analyzeItem(_ item: MediaItem, context: ModelContext) async {
        // Check for API key
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "openai") ?? .openai
        guard KeychainService.exists(service: provider.keychainService) else {
            print("[Analysis] No API key for \(provider.rawValue), skipping")
            return
        }

        let model = UserDefaults.standard.string(forKey: "\(provider.rawValue)Model") ?? provider.defaultModel
        print("[Analysis] Starting analysis with \(provider.rawValue)/\(model) for \(item.id)")

        item.isAnalyzing = true
        try? context.save()

        do {
            let result: AnalysisResult
            let storage = self.storage

            if item.isVideo {
                let frames = try await VideoFrameExtractor.extractAnalysisFrames(from: storage.mediaURL(filename: item.filename))
                result = try await analysisService.analyzeVideo(frames: frames, provider: provider, model: model)
            } else {
                guard let image = NSImage(contentsOf: storage.mediaURL(filename: item.filename)) else {
                    throw ImportError.cannotReadDimensions
                }

                // Get space-specific prompt
                var spacePrompt: String?
                if let space = item.space, space.useCustomPrompt, let prompt = space.customPrompt {
                    spacePrompt = "This image belongs to a collection called \"\(space.name)\". \(prompt)"
                }

                result = try await analysisService.analyze(image: image, provider: provider, model: model, spacePrompt: spacePrompt)
            }

            print("[Analysis] Success for \(item.id): \(result.patterns.count) patterns")
            item.analysisResult = result
            item.isAnalyzing = false
            item.analysisError = nil
            try? context.save()
        } catch {
            print("[Analysis] Failed for \(item.id): \(error)")
            item.isAnalyzing = false
            item.analysisError = error.localizedDescription
            try? context.save()
        }
    }

    enum ImportError: LocalizedError {
        case unsupportedFileType(String)
        case cannotReadDimensions

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let ext): return "Unsupported file type: .\(ext)"
            case .cannotReadDimensions: return "Cannot read image dimensions"
            }
        }
    }
}
