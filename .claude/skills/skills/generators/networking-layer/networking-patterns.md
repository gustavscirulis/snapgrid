# Networking Patterns and Best Practices

## Protocol-Based Architecture

### Why Protocols?

1. **Testability** - Use MockAPIClient in tests
2. **Flexibility** - Swap implementations (URLSession, custom)
3. **Abstraction** - Hide URLSession details from rest of app

### Core Protocol

```swift
protocol APIClient: Sendable {
    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response
}
```

### Endpoint Protocol

```swift
protocol APIEndpoint {
    associatedtype Response: Decodable

    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem]? { get }
    var body: Data? { get }
}

// Defaults
extension APIEndpoint {
    var method: HTTPMethod { .get }
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem]? { nil }
    var body: Data? { nil }
}
```

## Error Handling

### Typed Errors

```swift
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingFailed(Error)
    case httpError(statusCode: Int, data: Data?)
    case networkUnavailable
    case timeout
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingFailed(let error):
            return "Failed to decode: \(error.localizedDescription)"
        case .httpError(let code, _):
            return "HTTP error: \(code)"
        case .networkUnavailable:
            return "Network unavailable"
        case .timeout:
            return "Request timed out"
        case .unauthorized:
            return "Unauthorized - please sign in again"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
```

### Error Mapping

```swift
func mapHTTPError(statusCode: Int, data: Data?) -> NetworkError {
    switch statusCode {
    case 401:
        return .unauthorized
    case 403:
        return .httpError(statusCode: statusCode, data: data)
    case 404:
        return .httpError(statusCode: statusCode, data: data)
    case 500...599:
        let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        return .serverError(message)
    default:
        return .httpError(statusCode: statusCode, data: data)
    }
}
```

## Authentication Patterns

### Bearer Token

```swift
struct APIConfiguration {
    let baseURL: URL
    var authToken: String?

    func authorizationHeader() -> [String: String] {
        guard let token = authToken else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
}
```

### API Key

```swift
struct APIConfiguration {
    let baseURL: URL
    let apiKey: String
    let apiKeyLocation: APIKeyLocation

    enum APIKeyLocation {
        case header(name: String)
        case queryParam(name: String)
    }
}
```

### Token Refresh

```swift
actor TokenManager {
    private var token: String?
    private var refreshTask: Task<String, Error>?

    func validToken() async throws -> String {
        if let token = token, !isExpired(token) {
            return token
        }

        // Avoid multiple simultaneous refresh calls
        if let refreshTask = refreshTask {
            return try await refreshTask.value
        }

        let task = Task {
            let newToken = try await refreshToken()
            self.token = newToken
            return newToken
        }

        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }
}
```

## Retry Logic

### Exponential Backoff

```swift
struct RetryPolicy {
    let maxRetries: Int
    let initialDelay: TimeInterval
    let multiplier: Double
    let retryableErrors: Set<Int>

    static let `default` = RetryPolicy(
        maxRetries: 3,
        initialDelay: 1.0,
        multiplier: 2.0,
        retryableErrors: [408, 429, 500, 502, 503, 504]
    )

    func delay(for attempt: Int) -> TimeInterval {
        initialDelay * pow(multiplier, Double(attempt))
    }

    func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        attempt < maxRetries && retryableErrors.contains(statusCode)
    }
}
```

### Implementation

```swift
func requestWithRetry<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
    var lastError: Error?

    for attempt in 0..<retryPolicy.maxRetries {
        do {
            return try await request(endpoint)
        } catch let error as NetworkError {
            lastError = error

            if case .httpError(let code, _) = error,
               retryPolicy.shouldRetry(statusCode: code, attempt: attempt) {
                let delay = retryPolicy.delay(for: attempt)
                try await Task.sleep(for: .seconds(delay))
                continue
            }

            throw error
        }
    }

    throw lastError ?? NetworkError.noData
}
```

## Request/Response Logging

### Debug Logging

```swift
struct NetworkLogger {
    static func logRequest(_ request: URLRequest) {
        #if DEBUG
        print("➡️ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
        if let headers = request.allHTTPHeaderFields {
            print("   Headers: \(headers)")
        }
        if let body = request.httpBody, let string = String(data: body, encoding: .utf8) {
            print("   Body: \(string)")
        }
        #endif
    }

    static func logResponse(_ response: HTTPURLResponse, data: Data?, duration: TimeInterval) {
        #if DEBUG
        let emoji = (200...299).contains(response.statusCode) ? "✅" : "❌"
        print("\(emoji) \(response.statusCode) (\(String(format: "%.2f", duration))s)")
        if let data = data, let string = String(data: data, encoding: .utf8) {
            print("   Response: \(string.prefix(500))")
        }
        #endif
    }
}
```

## Swift 6.2 Concurrency Patterns

### Background Processing with @concurrent

For CPU-intensive work like JSON parsing:

```swift
final class URLSessionAPIClient: APIClient {
    // Heavy parsing runs on background thread
    @concurrent
    private static func decode<T: Decodable>(_ data: Data) async throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        let (data, response) = try await session.data(for: request)
        // ... validate response ...
        return try await Self.decode(data)
    }
}
```

### MainActor Integration

```swift
@MainActor
class NetworkViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var error: NetworkError?

    private let apiClient: APIClient

    func fetch() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await apiClient.request(ItemsEndpoint())
        } catch let error as NetworkError {
            self.error = error
        }
    }
}
```

## Caching Patterns

### URLCache Configuration

```swift
let cache = URLCache(
    memoryCapacity: 10 * 1024 * 1024,  // 10 MB memory
    diskCapacity: 50 * 1024 * 1024     // 50 MB disk
)

let configuration = URLSessionConfiguration.default
configuration.urlCache = cache
configuration.requestCachePolicy = .returnCacheDataElseLoad
```

### Custom Caching

```swift
actor ResponseCache {
    private var cache: [String: (data: Data, expiry: Date)] = [:]

    func get<T: Decodable>(_ key: String) -> T? {
        guard let entry = cache[key], entry.expiry > Date() else {
            cache.removeValue(forKey: key)
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: entry.data)
    }

    func set(_ key: String, data: Data, ttl: TimeInterval = 300) {
        cache[key] = (data, Date().addingTimeInterval(ttl))
    }
}
```

## Testing Patterns

### Mock Client

```swift
final class MockAPIClient: APIClient {
    private var responses: [String: Any] = [:]
    private var errors: [String: Error] = [:]

    func mockResponse<E: APIEndpoint>(for type: E.Type, response: E.Response) {
        responses[String(describing: type)] = response
    }

    func mockError<E: APIEndpoint>(for type: E.Type, error: Error) {
        errors[String(describing: type)] = error
    }

    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        let key = String(describing: E.self)

        if let error = errors[key] {
            throw error
        }

        guard let response = responses[key] as? E.Response else {
            throw NetworkError.noData
        }

        return response
    }
}
```

### Testing Example

```swift
@Test
func fetchUsersSuccess() async throws {
    let mockClient = MockAPIClient()
    mockClient.mockResponse(for: UsersEndpoint.self, response: [.mock])

    let viewModel = UsersViewModel(apiClient: mockClient)
    await viewModel.fetch()

    #expect(viewModel.users.count == 1)
    #expect(viewModel.error == nil)
}

@Test
func fetchUsersError() async throws {
    let mockClient = MockAPIClient()
    mockClient.mockError(for: UsersEndpoint.self, error: NetworkError.networkUnavailable)

    let viewModel = UsersViewModel(apiClient: mockClient)
    await viewModel.fetch()

    #expect(viewModel.users.isEmpty)
    #expect(viewModel.error == .networkUnavailable)
}
```

## Anti-Patterns to Avoid

### Don't Use Stringly-Typed APIs
```swift
// Bad
func fetch(path: String) async throws -> Data

// Good
func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response
```

### Don't Ignore Errors
```swift
// Bad
let data = try? await fetch()

// Good
do {
    let data = try await fetch()
} catch {
    handleError(error)
}
```

### Don't Block Main Thread
```swift
// Bad - synchronous on main
let data = try Data(contentsOf: url)

// Good - async
let (data, _) = try await URLSession.shared.data(from: url)
```
