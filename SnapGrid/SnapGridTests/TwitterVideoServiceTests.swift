import Testing
import Foundation
@testable import SnapGrid

@Suite("TwitterVideoService", .tags(.parsing))
struct TwitterVideoServiceTests {

    // MARK: - isTwitterURL

    @Test("Recognizes twitter.com status URLs")
    func twitterComStatus() {
        let url = URL(string: "https://twitter.com/user/status/1234567890")!
        #expect(TwitterVideoService.isTwitterURL(url) == true)
    }

    @Test("Recognizes x.com status URLs")
    func xComStatus() {
        let url = URL(string: "https://x.com/user/status/1234567890")!
        #expect(TwitterVideoService.isTwitterURL(url) == true)
    }

    @Test("Recognizes www.x.com URLs")
    func wwwXComStatus() {
        let url = URL(string: "https://www.x.com/user/status/1234567890")!
        #expect(TwitterVideoService.isTwitterURL(url) == true)
    }

    @Test("Recognizes mobile.twitter.com URLs")
    func mobileTwitterStatus() {
        let url = URL(string: "https://mobile.twitter.com/user/status/1234567890")!
        #expect(TwitterVideoService.isTwitterURL(url) == true)
    }

    @Test("Rejects non-Twitter URLs")
    func rejectsNonTwitter() {
        let url = URL(string: "https://youtube.com/watch?v=123")!
        #expect(TwitterVideoService.isTwitterURL(url) == false)
    }

    @Test("Rejects Twitter URLs without status path")
    func rejectsNoStatusPath() {
        let url = URL(string: "https://twitter.com/user")!
        #expect(TwitterVideoService.isTwitterURL(url) == false)
    }

    // MARK: - extractTweetId

    @Test("Extracts tweet ID from standard URL")
    func extractStandardId() {
        let url = URL(string: "https://x.com/user/status/1234567890123456789")!
        #expect(TwitterVideoService.extractTweetId(from: url) == "1234567890123456789")
    }

    @Test("Extracts tweet ID with trailing path components")
    func extractIdWithTrailing() {
        let url = URL(string: "https://x.com/user/status/1234567890/photo/1")!
        #expect(TwitterVideoService.extractTweetId(from: url) == "1234567890")
    }

    @Test("Returns nil for URL without status segment")
    func noStatusSegment() {
        let url = URL(string: "https://x.com/user/likes")!
        #expect(TwitterVideoService.extractTweetId(from: url) == nil)
    }

    @Test("Returns nil when status has no ID after it")
    func statusNoId() {
        let url = URL(string: "https://x.com/user/status")!
        #expect(TwitterVideoService.extractTweetId(from: url) == nil)
    }
}
