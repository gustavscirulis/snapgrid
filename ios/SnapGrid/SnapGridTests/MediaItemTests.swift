import Testing
import Foundation
import SwiftData
@testable import SnapGrid

@Suite("MediaItem", .tags(.model))
@MainActor
struct MediaItemTests {

    @Test("Aspect ratio for landscape image")
    func landscapeAspectRatio() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 1920, height: 1080)
        container.mainContext.insert(item)
        #expect(abs(item.aspectRatio - 1.7778) < 0.001)
    }

    @Test("Aspect ratio for portrait image")
    func portraitAspectRatio() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 1080, height: 1920)
        container.mainContext.insert(item)
        #expect(abs(item.aspectRatio - 0.5625) < 0.001)
    }

    @Test("Aspect ratio with zero height returns 1.0")
    func zeroHeightAspectRatio() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 0)
        container.mainContext.insert(item)
        #expect(item.aspectRatio == 1.0)
    }

    @Test("isVideo true for video type")
    func isVideoTrue() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .video, filename: "vid.mp4", width: 1920, height: 1080, duration: 10.0)
        container.mainContext.insert(item)
        #expect(item.isVideo == true)
    }

    @Test("isVideo false for image type")
    func isVideoFalse() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        container.mainContext.insert(item)
        #expect(item.isVideo == false)
    }

    // MARK: - iOS-specific: gridAspectRatio

    @Test("gridAspectRatio caps tall images at 0.5")
    func gridAspectRatioCapped() throws {
        let container = try TestContainer.create()
        // Very tall screenshot: 390x2000 → aspectRatio ~0.195
        let item = MediaItem(mediaType: .image, filename: "tall.png", width: 390, height: 2000)
        container.mainContext.insert(item)
        #expect(item.gridAspectRatio == 0.5)
    }

    @Test("gridAspectRatio unchanged for normal images")
    func gridAspectRatioNormal() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 1920, height: 1080)
        container.mainContext.insert(item)
        #expect(item.gridAspectRatio == item.aspectRatio)
    }

    @Test("gridAspectRatio exactly 0.5 stays at 0.5")
    func gridAspectRatioExactly05() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 500, height: 1000)
        container.mainContext.insert(item)
        #expect(item.gridAspectRatio == 0.5)
    }

    // MARK: - sourceURL (PR #150)

    @Test("sourceURL property stores and retrieves")
    func sourceURLProperty() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .video, filename: "vid.mp4", width: 1280, height: 720)
        container.mainContext.insert(item)
        item.sourceURL = "https://x.com/user/status/123"
        #expect(item.sourceURL == "https://x.com/user/status/123")
    }

    @Test("sourceURL defaults to nil")
    func sourceURLDefaultsNil() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        container.mainContext.insert(item)
        #expect(item.sourceURL == nil)
    }
}
