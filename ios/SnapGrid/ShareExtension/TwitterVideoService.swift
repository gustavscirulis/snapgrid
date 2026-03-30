import Foundation

/// Lightweight X/Twitter video extractor for the share extension.
/// Mirrors the Mac app's `TwitterVideoService` using the syndication API.
enum TwitterVideoService {

    private static let twitterHosts: Set<String> = [
        "x.com", "www.x.com",
        "twitter.com", "www.twitter.com",
        "mobile.twitter.com",
    ]

    /// Returns `true` when the URL looks like an X / Twitter post.
    static func isTwitterURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), twitterHosts.contains(host) else { return false }
        return extractTweetId(from: url) != nil
    }

    /// Fetches the tweet via the syndication API and returns the best MP4 URL
    /// that fits within share-extension constraints (capped at 720p to stay
    /// within the ~30-second execution window).
    static func extractVideoURL(from tweetURL: URL) async throws -> URL {
        guard let tweetId = extractTweetId(from: tweetURL) else {
            throw TwitterError.invalidURL
        }

        let apiURL = URL(string: "https://cdn.syndication.twimg.com/tweet-result?id=\(tweetId)&token=x")!

        var request = URLRequest(url: apiURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TwitterError.apiRequestFailed(0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw TwitterError.apiRequestFailed(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mediaDetails = json["mediaDetails"] as? [[String: Any]] else {
            throw TwitterError.malformedResponse
        }

        guard let videoMedia = mediaDetails.first(where: {
            let type = $0["type"] as? String
            return type == "video" || type == "animated_gif"
        }) else {
            throw TwitterError.noVideoInTweet
        }

        guard let videoInfo = videoMedia["video_info"] as? [String: Any],
              let variants = videoInfo["variants"] as? [[String: Any]] else {
            throw TwitterError.malformedResponse
        }

        // Filter to MP4, pick highest bitrate up to ~720p (2.2 Mbps) to keep
        // downloads fast within the extension's time budget. If no variant is
        // under the cap, fall back to the smallest available.
        let mp4Variants = variants
            .filter { ($0["content_type"] as? String) == "video/mp4" }
            .compactMap { variant -> (url: String, bitrate: Int)? in
                guard let url = variant["url"] as? String,
                      let bitrate = variant["bitrate"] as? Int else { return nil }
                return (url, bitrate)
            }
            .sorted { $0.bitrate < $1.bitrate }

        let maxBitrate = 2_500_000 // ~720p cap
        let best = mp4Variants.last(where: { $0.bitrate <= maxBitrate }) ?? mp4Variants.last

        guard let chosen = best, let videoURL = URL(string: chosen.url) else {
            throw TwitterError.noVideoInTweet
        }

        return videoURL
    }

    // MARK: - Helpers

    private static func extractTweetId(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let statusIndex = parts.firstIndex(of: "status"),
              statusIndex + 1 < parts.count else { return nil }
        let candidate = parts[statusIndex + 1]
        let digits = candidate.prefix(while: \.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    // MARK: - Errors

    enum TwitterError: LocalizedError {
        case invalidURL
        case noVideoInTweet
        case apiRequestFailed(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Not a valid X post URL"
            case .noVideoInTweet:
                return "This post doesn't contain a video"
            case .apiRequestFailed(let code):
                return "Couldn't fetch post data from X (HTTP \(code))"
            case .malformedResponse:
                return "Couldn't parse post data from X"
            }
        }
    }
}
