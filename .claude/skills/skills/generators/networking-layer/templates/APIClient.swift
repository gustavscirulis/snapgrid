import Foundation

// MARK: - Protocol

/// Protocol defining the API client interface.
///
/// Use this protocol for dependency injection and testing.
/// The default implementation uses URLSession.
protocol APIClient: Sendable {
    /// Execute a request for the given endpoint.
    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response
}

// MARK: - URLSession Implementation

/// URLSession-based API client implementation.
///
/// Usage:
/// ```swift
/// let client = URLSessionAPIClient(configuration: .production)
/// let users = try await client.request(UsersEndpoint())
/// ```
final class URLSessionAPIClient: APIClient, Sendable {

    private let session: URLSession
    private let configuration: APIConfiguration
    private let decoder: JSONDecoder

    init(
        configuration: APIConfiguration,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
    }

    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        let urlRequest = try buildRequest(for: endpoint)

        #if DEBUG
        NetworkLogger.logRequest(urlRequest)
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        #if DEBUG
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        NetworkLogger.logResponse(httpResponse, data: data, duration: duration)
        #endif

        try validateResponse(httpResponse, data: data)

        return try decode(data)
    }

    // MARK: - Private

    private func buildRequest<E: APIEndpoint>(for endpoint: E) throws -> URLRequest {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: true)
        components?.path += endpoint.path

        if let queryItems = endpoint.queryItems {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body

        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Auth headers
        for (key, value) in configuration.authorizationHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Endpoint-specific headers
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw NetworkError.unauthorized
        case 400...499:
            throw NetworkError.httpError(statusCode: response.statusCode, data: data)
        case 500...599:
            let message = String(data: data, encoding: .utf8) ?? "Server error"
            throw NetworkError.serverError(message)
        default:
            throw NetworkError.httpError(statusCode: response.statusCode, data: data)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
}

// MARK: - Network Logger

struct NetworkLogger {
    static func logRequest(_ request: URLRequest) {
        #if DEBUG
        print("➡️ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
        if let headers = request.allHTTPHeaderFields?.filter({ !$0.key.contains("Authorization") }) {
            print("   Headers: \(headers)")
        }
        if let body = request.httpBody, let string = String(data: body, encoding: .utf8) {
            print("   Body: \(string.prefix(500))")
        }
        #endif
    }

    static func logResponse(_ response: HTTPURLResponse, data: Data?, duration: TimeInterval) {
        #if DEBUG
        let emoji = (200...299).contains(response.statusCode) ? "✅" : "❌"
        print("\(emoji) \(response.statusCode) (\(String(format: "%.2fs", duration)))")
        if let data = data, let string = String(data: data, encoding: .utf8) {
            let truncated = string.count > 500 ? "\(string.prefix(500))..." : string
            print("   Response: \(truncated)")
        }
        #endif
    }
}
