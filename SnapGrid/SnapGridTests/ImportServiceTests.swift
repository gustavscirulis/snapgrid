import Testing
import Foundation
@testable import SnapGrid

@Suite("ImportService Helpers", .tags(.parsing))
@MainActor
struct ImportServiceTests {

    @Test("MIME image/png maps to png")
    func mimePng() {
        #expect(ImportService.fileExtension(from: "image/png", urlPathExtension: nil) == "png")
    }

    @Test("MIME image/jpeg maps to jpg")
    func mimeJpeg() {
        #expect(ImportService.fileExtension(from: "image/jpeg", urlPathExtension: nil) == "jpg")
    }

    @Test("MIME video/mp4 maps to mp4")
    func mimeMp4() {
        #expect(ImportService.fileExtension(from: "video/mp4", urlPathExtension: nil) == "mp4")
    }

    @Test("MIME video/quicktime maps to mov")
    func mimeMov() {
        #expect(ImportService.fileExtension(from: "video/quicktime", urlPathExtension: nil) == "mov")
    }

    @Test("MIME with charset parameter is handled")
    func mimeWithCharset() {
        #expect(ImportService.fileExtension(from: "image/png; charset=utf-8", urlPathExtension: nil) == "png")
    }

    @Test("Falls back to URL extension when MIME unknown")
    func fallbackToUrlExtension() {
        #expect(ImportService.fileExtension(from: "application/octet-stream", urlPathExtension: "jpg") == "jpg")
    }

    @Test("Falls back to URL extension when MIME nil")
    func nilMimeFallback() {
        #expect(ImportService.fileExtension(from: nil, urlPathExtension: "png") == "png")
    }

    @Test("Returns nil for unknown MIME and unknown extension")
    func unknownBoth() {
        #expect(ImportService.fileExtension(from: "application/octet-stream", urlPathExtension: "xyz") == nil)
    }

    @Test("Returns nil when both are nil")
    func bothNil() {
        #expect(ImportService.fileExtension(from: nil, urlPathExtension: nil) == nil)
    }

    @Test("MIME takes precedence over URL extension")
    func mimePrecedence() {
        // MIME says JPEG, URL says PNG — MIME wins
        #expect(ImportService.fileExtension(from: "image/jpeg", urlPathExtension: "png") == "jpg")
    }

    @Test("All supported image MIME types map correctly",
          arguments: [
            ("image/png", "png"), ("image/jpeg", "jpg"), ("image/gif", "gif"),
            ("image/webp", "webp"), ("image/bmp", "bmp"), ("image/tiff", "tiff"),
            ("image/heic", "heic")
          ])
    func allImageMimes(_ mime: String, _ expected: String) {
        #expect(ImportService.fileExtension(from: mime, urlPathExtension: nil) == expected)
    }

    @Test("All supported video MIME types map correctly",
          arguments: [
            ("video/mp4", "mp4"), ("video/webm", "webm"),
            ("video/quicktime", "mov"), ("video/x-msvideo", "avi"),
            ("video/x-m4v", "m4v")
          ])
    func allVideoMimes(_ mime: String, _ expected: String) {
        #expect(ImportService.fileExtension(from: mime, urlPathExtension: nil) == expected)
    }
}
