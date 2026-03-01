import Foundation

/// Errors that can occur during network requests.
///
/// Use these typed errors for better error handling and user messaging.
enum NetworkError: Error, LocalizedError, Sendable {

    /// The URL could not be constructed.
    case invalidURL

    /// The response was not an HTTP response.
    case invalidResponse

    /// No data was received.
    case noData

    /// Failed to decode the response.
    case decodingFailed(Error)

    /// HTTP error with status code.
    case httpError(statusCode: Int, data: Data?)

    /// Network is unavailable.
    case networkUnavailable

    /// Request timed out.
    case timeout

    /// Authentication required (401).
    case unauthorized

    /// Access forbidden (403).
    case forbidden

    /// Resource not found (404).
    case notFound

    /// Server error (5xx).
    case serverError(String)

    /// Request was cancelled.
    case cancelled

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .noData:
            return "No data received"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .httpError(let code, _):
            return "Request failed with status \(code)"
        case .networkUnavailable:
            return "Network unavailable. Please check your connection."
        case .timeout:
            return "Request timed out. Please try again."
        case .unauthorized:
            return "Please sign in to continue"
        case .forbidden:
            return "You don't have permission to access this"
        case .notFound:
            return "The requested resource was not found"
        case .serverError(let message):
            return "Server error: \(message)"
        case .cancelled:
            return "Request was cancelled"
        }
    }

    /// A user-friendly message for display in UI.
    var userMessage: String {
        switch self {
        case .networkUnavailable:
            return "No internet connection. Please check your network settings."
        case .timeout:
            return "The request took too long. Please try again."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .serverError:
            return "Something went wrong on our end. Please try again later."
        default:
            return errorDescription ?? "An unexpected error occurred"
        }
    }

    /// Whether the error is retryable.
    var isRetryable: Bool {
        switch self {
        case .timeout, .networkUnavailable, .serverError:
            return true
        case .httpError(let code, _):
            return [408, 429, 500, 502, 503, 504].contains(code)
        default:
            return false
        }
    }
}

// MARK: - Equatable (for testing)

extension NetworkError: Equatable {
    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.noData, .noData),
             (.networkUnavailable, .networkUnavailable),
             (.timeout, .timeout),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.notFound, .notFound),
             (.cancelled, .cancelled):
            return true
        case (.httpError(let lhsCode, _), .httpError(let rhsCode, _)):
            return lhsCode == rhsCode
        case (.serverError(let lhsMsg), .serverError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.decodingFailed, .decodingFailed):
            return true  // Don't compare underlying errors
        default:
            return false
        }
    }
}
