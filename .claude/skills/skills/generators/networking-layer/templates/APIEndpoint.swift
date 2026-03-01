import Foundation

// MARK: - HTTP Method

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - Endpoint Protocol

/// Protocol defining an API endpoint.
///
/// Implement this protocol for each endpoint in your API.
///
/// Example:
/// ```swift
/// struct UsersEndpoint: APIEndpoint {
///     typealias Response = [User]
///
///     var path: String { "/users" }
/// }
///
/// struct CreateUserEndpoint: APIEndpoint {
///     typealias Response = User
///
///     let user: CreateUserRequest
///
///     var path: String { "/users" }
///     var method: HTTPMethod { .post }
///     var body: Data? {
///         try? JSONEncoder().encode(user)
///     }
/// }
/// ```
protocol APIEndpoint: Sendable {
    /// The response type returned by this endpoint.
    associatedtype Response: Decodable & Sendable

    /// The path component of the URL (e.g., "/users").
    var path: String { get }

    /// The HTTP method (default: GET).
    var method: HTTPMethod { get }

    /// Additional headers for this endpoint.
    var headers: [String: String] { get }

    /// Query parameters for the URL.
    var queryItems: [URLQueryItem]? { get }

    /// Request body data.
    var body: Data? { get }
}

// MARK: - Default Implementations

extension APIEndpoint {
    var method: HTTPMethod { .get }
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem]? { nil }
    var body: Data? { nil }
}

// MARK: - Convenience for JSON Body

extension APIEndpoint {
    /// Encode an Encodable value as JSON body.
    func jsonBody<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}

// MARK: - Example Endpoints

/*

// GET /users
struct UsersEndpoint: APIEndpoint {
    typealias Response = [User]
    var path: String { "/users" }
}

// GET /users/:id
struct UserEndpoint: APIEndpoint {
    typealias Response = User
    let id: String
    var path: String { "/users/\(id)" }
}

// POST /users
struct CreateUserEndpoint: APIEndpoint {
    typealias Response = User
    let request: CreateUserRequest

    var path: String { "/users" }
    var method: HTTPMethod { .post }
    var body: Data? { jsonBody(request) }
}

// GET /users?role=admin&limit=10
struct FilteredUsersEndpoint: APIEndpoint {
    typealias Response = [User]
    let role: String?
    let limit: Int

    var path: String { "/users" }
    var queryItems: [URLQueryItem]? {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let role = role {
            items.append(URLQueryItem(name: "role", value: role))
        }
        return items
    }
}

// DELETE /users/:id
struct DeleteUserEndpoint: APIEndpoint {
    typealias Response = EmptyResponse
    let id: String

    var path: String { "/users/\(id)" }
    var method: HTTPMethod { .delete }
}

*/

// MARK: - Empty Response

/// Use for endpoints that return no data (e.g., DELETE).
struct EmptyResponse: Decodable, Sendable {}
