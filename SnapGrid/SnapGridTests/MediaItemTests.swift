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

    @Test("Aspect ratio for square image")
    func squareAspectRatio() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 500, height: 500)
        container.mainContext.insert(item)
        #expect(item.aspectRatio == 1.0)
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
        let item = MediaItem(mediaType: .video, filename: "vid_test.mp4", width: 1920, height: 1080, duration: 10.0)
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

    @Test("Default id is generated UUID")
    func defaultId() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        container.mainContext.insert(item)
        #expect(!item.id.isEmpty)
        #expect(UUID(uuidString: item.id) != nil)
    }

    @Test("Duration stored for video items")
    func videoDuration() throws {
        let container = try TestContainer.create()
        let item = MediaItem(mediaType: .video, filename: "vid.mp4", width: 1920, height: 1080, duration: 42.5)
        container.mainContext.insert(item)
        #expect(item.duration == 42.5)
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
