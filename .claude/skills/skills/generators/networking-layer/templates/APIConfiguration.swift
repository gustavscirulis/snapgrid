import Foundation

/// Configuration for the API client.
///
/// Define your environments and authentication here.
///
/// Usage:
/// ```swift
/// // Single environment
/// let config = APIConfiguration(baseURL: URL(string: "https://api.example.com")!)
///
/// // With authentication
/// var config = APIConfiguration.production
/// config.authToken = userToken
///
/// // Create client
/// let client = URLSessionAPIClient(configuration: config)
/// ```
struct APIConfiguration: Sendable {

    /// The base URL for all API requests.
    let baseURL: URL

    /// Optional bearer token for authentication.
    var authToken: String?

    /// Optional API key for authentication.
    var apiKey: String?

    /// Where to send the API key (header or query param).
    var apiKeyLocation: APIKeyLocation?

    /// Custom headers to include in all requests.
    var customHeaders: [String: String] = [:]

    // MARK: - Initialization

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - Environments

    /// Production environment.
    static var production: APIConfiguration {
        // TODO: Replace with your production URL
        APIConfiguration(baseURL: URL(string: "https://api.example.com/v1")!)
    }

    /// Development/staging environment.
    static var development: APIConfiguration {
        // TODO: Replace with your development URL
        APIConfiguration(baseURL: URL(string: "https://dev-api.example.com/v1")!)
    }

    #if DEBUG
    /// Local development server.
    static var local: APIConfiguration {
        APIConfiguration(baseURL: URL(string: "http://localhost:8080/v1")!)
    }
    #endif

    // MARK: - Authorization Headers

    /// Build authorization headers based on configuration.
    func authorizationHeaders() -> [String: String] {
        var headers = customHeaders

        // Bearer token
        if let token = authToken {
            headers["Authorization"] = "Bearer \(token)"
        }

        // API key in header
        if let apiKey = apiKey, case .header(let name) = apiKeyLocation {
            headers[name] = apiKey
        }

        return headers
    }

    /// Build query items for API key if configured.
    func authorizationQueryItems() -> [URLQueryItem]? {
        guard let apiKey = apiKey, case .queryParam(let name) = apiKeyLocation else {
            return nil
        }
        return [URLQueryItem(name: name, value: apiKey)]
    }
}

// MARK: - API Key Location

extension APIConfiguration {
    /// Where to include the API key in requests.
    enum APIKeyLocation: Sendable {
        /// Include API key in request header.
        case header(name: String)

        /// Include API key as query parameter.
        case queryParam(name: String)

        // Common presets
        static let xApiKey = APIKeyLocation.header(name: "X-API-Key")
        static let authorization = APIKeyLocation.header(name: "Authorization")
        static let apiKeyQuery = APIKeyLocation.queryParam(name: "api_key")
    }
}

// MARK: - SwiftUI Environment Integration

import SwiftUI

/// Environment key for API client.
private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient = URLSessionAPIClient(configuration: .production)
}

extension EnvironmentValues {
    var apiClient: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
