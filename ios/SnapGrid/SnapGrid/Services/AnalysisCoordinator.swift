import AVFoundation
import SwiftData
import UIKit

/// Coordinates AI analysis of media items, extracting this logic from MainView.
@Observable
@MainActor
final class AnalysisCoordinator {
    private var analysisTask: Task<Void, Never>?

    /// Analyze all unanalyzed items, or re-analyze a single item.
    func analyzeItems(
        _ items: [MediaItem],
        keySyncService: KeySyncService,
        fileSystem: FileSystemManager,
        modelContext: ModelContext,
        searchService: SearchIndexService,
        allItems: [MediaItem]
    ) {
        guard keySyncService.isUnlocked else {
            print("[Analysis] Skipped — keySyncService not unlocked")
            return
        }
        guard let providerStr = keySyncService.activeProvider,
              let provider = AIProvider(rawValue: providerStr) else {
            print("[Analysis] Skipped — no active provider")
            return
        }
        guard let apiKey = keySyncService.activeAPIKey() else {
            print("[Analysis] Skipped — no API key for provider \(providerStr)")
            return
        }
        guard let rootURL = fileSystem.rootURL else {
            print("[Analysis] Skipped — no rootURL")
            return
        }

        let model = keySyncService.activeModel ?? provider.defaultModel
        let resolvedModel = (model == "auto") ? provider.defaultModel : model

        guard !items.isEmpty else {
            print("[Analysis] No items to analyze")
            return
        }

        print("[Analysis] Starting analysis of \(items.count) item(s)")

        analysisTask?.cancel()
        analysisTask = Task {
            for item in items {
                guard !Task.isCancelled else { break }

                item.isAnalyzing = true
                do {
                    let (guidance, spaceContext) = resolveGuidance(for: item)

                    let result: AnalysisResult
                    if item.isVideo {
                        let frames = try extractVideoFrames(for: item, rootURL: rootURL)
                        result = try await AIAnalysisService.shared.analyzeVideo(
                            frames: frames,
                            provider: provider,
                            model: resolvedModel,
                            apiKey: apiKey,
                            guidance: guidance,
                            spaceContext: spaceContext
                        )
                    } else {
                        let image = try loadImage(for: item, rootURL: rootURL)
                        result = try await AIAnalysisService.shared.analyze(
                            image: image,
                            provider: provider,
                            model: resolvedModel,
                            apiKey: apiKey,
                            guidance: guidance,
                            spaceContext: spaceContext
                        )
                    }
                    item.analysisResult = result
                    item.isAnalyzing = false
                    item.analysisError = nil

                    SidecarWriteService.writeAnalysis(for: item, rootURL: rootURL)
                    searchService.buildIndex(items: allItems)
                    modelContext.saveOrLog()
                    print("[Analysis] Completed: \(item.id)")
                } catch {
                    item.isAnalyzing = false
                    item.analysisError = error.localizedDescription
                    print("[Analysis] Failed for \(item.id): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Find and analyze all unanalyzed items.
    func analyzeUnanalyzed(
        keySyncService: KeySyncService,
        fileSystem: FileSystemManager,
        modelContext: ModelContext,
        searchService: SearchIndexService,
        allItems: [MediaItem]
    ) {
        let descriptor = FetchDescriptor<MediaItem>()
        let allCurrentItems = (try? modelContext.fetch(descriptor)) ?? []
        let unanalyzed = allCurrentItems.filter {
            $0.analysisResult == nil && !$0.isAnalyzing && $0.analysisError == nil
        }

        analyzeItems(
            unanalyzed,
            keySyncService: keySyncService,
            fileSystem: fileSystem,
            modelContext: modelContext,
            searchService: searchService,
            allItems: allItems
        )
    }

    // MARK: - Private Helpers

    private func loadImage(for item: MediaItem, rootURL: URL) throws -> UIImage {
        let fileURL = rootURL.appendingPathComponent("images/\(item.filename)")
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            throw AIAnalysisService.AnalysisError.imageConversionFailed
        }
        return image
    }

    /// Extract frames at 33% and 66% of video duration for multi-frame analysis,
    /// matching the Mac app's VideoFrameExtractor.extractAnalysisFrames behavior.
    private func extractVideoFrames(for item: MediaItem, rootURL: URL) throws -> [UIImage] {
        let fileURL = rootURL.appendingPathComponent("images/\(item.filename)")
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0 else {
            // Fall back to first frame for very short or broken videos
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return [UIImage(cgImage: cgImage)]
        }

        let fractions = [0.33, 0.66]
        var frames: [UIImage] = []
        for fraction in fractions {
            let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            frames.append(UIImage(cgImage: cgImage))
        }
        return frames
    }

    private func resolveGuidance(for item: MediaItem) -> (guidance: String?, spaceContext: String?) {
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

        return (guidance, spaceContext)
    }
}
