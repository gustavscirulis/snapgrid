import Foundation

/// Mock API client for testing.
///
/// Usage:
/// ```swift
/// let mockClient = MockAPIClient()
/// mockClient.mockResponse(for: UsersEndpoint.self, response: [.mock])
///
/// let viewModel = UsersViewModel(apiClient: mockClient)
/// await viewModel.fetch()
///
/// XCTAssertEqual(viewModel.users.count, 1)
/// ```
final class MockAPIClient: APIClient, @unchecked Sendable {

    // MARK: - Storage

    private var responses: [String: Any] = [:]
    private var errors: [String: Error] = [:]
    private var requestHistory: [String] = []
    private var delay: TimeInterval = 0

    // MARK: - Configuration

    /// Set artificial delay for all requests (useful for testing loading states).
    func setDelay(_ delay: TimeInterval) {
        self.delay = delay
    }

    /// Mock a successful response for an endpoint type.
    func mockResponse<E: APIEndpoint>(for type: E.Type, response: E.Response) {
        responses[key(for: type)] = response
    }

    /// Mock an error for an endpoint type.
    func mockError<E: APIEndpoint>(for type: E.Type, error: Error) {
        errors[key(for: type)] = error
    }

    /// Clear all mocks.
    func reset() {
        responses.removeAll()
        errors.removeAll()
        requestHistory.removeAll()
    }

    // MARK: - Request History

    /// Check if a specific endpoint was called.
    func wasCalled<E: APIEndpoint>(_ type: E.Type) -> Bool {
        requestHistory.contains(key(for: type))
    }

    /// Number of times an endpoint was called.
    func callCount<E: APIEndpoint>(_ type: E.Type) -> Int {
        requestHistory.filter { $0 == key(for: type) }.count
    }

    // MARK: - APIClient

    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        let endpointKey = key(for: E.self)
        requestHistory.append(endpointKey)

        // Artificial delay
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }

        // Check for mocked error
        if let error = errors[endpointKey] {
            throw error
        }

        // Check for mocked response
        guard let response = responses[endpointKey] as? E.Response else {
            throw NetworkError.noData
        }

        return response
    }

    // MARK: - Private

    private func key<E: APIEndpoint>(for type: E.Type) -> String {
        String(describing: type)
    }
}

// MARK: - Convenience Extensions

extension MockAPIClient {

    /// Mock a network unavailable error.
    func mockNetworkUnavailable<E: APIEndpoint>(for type: E.Type) {
        mockError(for: type, error: NetworkError.networkUnavailable)
    }

    /// Mock an unauthorized error.
    func mockUnauthorized<E: APIEndpoint>(for type: E.Type) {
        mockError(for: type, error: NetworkError.unauthorized)
    }

    /// Mock a server error.
    func mockServerError<E: APIEndpoint>(for type: E.Type, message: String = "Internal Server Error") {
        mockError(for: type, error: NetworkError.serverError(message))
    }
}
