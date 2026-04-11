import Testing
import UIKit
import Foundation
@testable import SnapGrid

@Suite("ImageImportService", .tags(.filesystem))
struct ImageImportServiceTests {

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapGridImportTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeTestImage(width: Int = 100, height: Int = 100) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test("Single image import creates png and json files")
    func singleImageImport() async throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }

        let image = makeTestImage()
        let result = await ImageImportService.importImages([image], to: root)

        #expect(result.successCount == 1)
        #expect(result.failureCount == 0)

        let imagesDir = root.appendingPathComponent("images")
        let metadataDir = root.appendingPathComponent("metadata")
        let imageFiles = try FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)

        #expect(imageFiles.count == 1)
        #expect(jsonFiles.count == 1)
        #expect(imageFiles[0].pathExtension == "png")
        #expect(jsonFiles[0].pathExtension == "json")
    }

    @Test("Sidecar JSON contains correct dimensions")
    func sidecarDimensions() async throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }

        let image = makeTestImage(width: 200, height: 150)
        _ = await ImageImportService.importImages([image], to: root)

        let metadataDir = root.appendingPathComponent("metadata")
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)
        let data = try Data(contentsOf: jsonFiles[0])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(SidecarMetadata.self, from: data)

        // UIImage dimensions are in points, sidecar stores pixels (size * scale)
        // Simulator scale varies (e.g. @3x on iPhone 17 Pro), so verify ratio
        #expect(sidecar.width > 0)
        #expect(sidecar.height > 0)
        // Aspect ratio should match: 200/150 = 4/3
        let ratio = Double(sidecar.width) / Double(sidecar.height)
        #expect(abs(ratio - 4.0/3.0) < 0.01)
        #expect(sidecar.type == "image")
    }

    @Test("spaceId parameter is normalized to spaceIds in sidecar")
    func spaceIdInSidecar() async throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }

        let image = makeTestImage()
        _ = await ImageImportService.importImages([image], to: root, spaceId: "space-42")

        let metadataDir = root.appendingPathComponent("metadata")
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)
        let data = try Data(contentsOf: jsonFiles[0])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(SidecarMetadata.self, from: data)

        #expect(sidecar.spaceIds == ["space-42"])
        #expect(sidecar.normalizedSpaceIDs == ["space-42"])
    }

    @Test("Multiple images returns correct counts")
    func multipleImages() async throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }

        let images = (0..<3).map { _ in makeTestImage() }
        let result = await ImageImportService.importImages(images, to: root)

        #expect(result.successCount == 3)
        #expect(result.failureCount == 0)

        let imageFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("images"),
            includingPropertiesForKeys: nil
        )
        #expect(imageFiles.count == 3)
    }

    @Test("Generated ID is a valid UUID")
    func idFormat() async throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }

        let image = makeTestImage()
        _ = await ImageImportService.importImages([image], to: root)

        let imageFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("images"),
            includingPropertiesForKeys: nil
        )
        let filename = imageFiles[0].deletingPathExtension().lastPathComponent
        // ID is a UUID string (e.g. "AB2D0053-8EEE-4D8D-A9B8-A9CB826BC718")
        #expect(UUID(uuidString: filename) != nil)
    }
}
