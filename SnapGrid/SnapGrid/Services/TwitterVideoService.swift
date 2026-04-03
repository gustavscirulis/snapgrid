import Foundation

enum TwitterVideoService {

    // MARK: - URL Detection

    private static let twitterHosts: Set<String> = [
        "x.com", "www.x.com",
        "twitter.com", "www.twitter.com",
        "mobile.twitter.com",
    ]

    /// Returns `true` when the URL looks like an X / Twitter post (contains `/status/{digits}`).
    static func isTwitterURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), twitterHosts.contains(host) else { return false }
        return extractTweetId(from: url) != nil
    }

    // MARK: - Media Extraction

    enum MediaResult {
        case video(URL)
        case image(URL)
    }

    /// Fetches the tweet via the syndication API and returns the best media URL (video or image).
    static func extractMediaURL(from tweetURL: URL) async throws -> MediaResult {
        guard let tweetId = extractTweetId(from: tweetURL) else {
            throw TwitterError.invalidURL
        }

        let apiURL = URL(string: "https://cdn.syndication.twimg.com/tweet-result?id=\(tweetId)&token=x")!

        var request = URLRequest(url: apiURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

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

        // Prefer video/animated_gif over photos.
        if let videoMedia = mediaDetails.first(where: {
            let type = $0["type"] as? String
            return type == "video" || type == "animated_gif"
        }) {
            guard let videoInfo = videoMedia["video_info"] as? [String: Any],
                  let variants = videoInfo["variants"] as? [[String: Any]] else {
                throw TwitterError.malformedResponse
            }

            let mp4Variant = variants
                .filter { ($0["content_type"] as? String) == "video/mp4" }
                .compactMap { variant -> (url: String, bitrate: Int)? in
                    guard let url = variant["url"] as? String,
                          let bitrate = variant["bitrate"] as? Int else { return nil }
                    return (url, bitrate)
                }
                .max(by: { $0.bitrate < $1.bitrate })

            guard let best = mp4Variant, let videoURL = URL(string: best.url) else {
                throw TwitterError.noMediaInTweet
            }

            return .video(videoURL)
        }

        // Fall back to photo.
        if let photoMedia = mediaDetails.first(where: { ($0["type"] as? String) == "photo" }),
           let mediaURLString = photoMedia["media_url_https"] as? String,
           let mediaURL = URL(string: mediaURLString + "?name=large") {
            return .image(mediaURL)
        }

        throw TwitterError.noMediaInTweet
    }

    // MARK: - Private Helpers

    /// Extracts the numeric tweet ID from a path like `/user/status/12345…`.
    static func extractTweetId(from url: URL) -> String? {
        let parts = url.pathComponents                       // e.g. ["/", "user", "status", "12345"]
        guard let statusIndex = parts.firstIndex(of: "status"),
              statusIndex + 1 < parts.count else { return nil }
        let candidate = parts[statusIndex + 1]
        // Strip any trailing non-digit characters (e.g. from /photo/1 appended without separator)
        let digits = candidate.prefix(while: \.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    // MARK: - Errors

    enum TwitterError: LocalizedError {
        case invalidURL
        case noMediaInTweet
        case apiRequestFailed(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Not a valid X post URL"
            case .noMediaInTweet:
                return "This post doesn't contain any media"
            case .apiRequestFailed(let code):
                return "Couldn't fetch post data from X (HTTP \(code))"
            case .malformedResponse:
                return "Couldn't parse post data from X"
            }
        }
    }
}
