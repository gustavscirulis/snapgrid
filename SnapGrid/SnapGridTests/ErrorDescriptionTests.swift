import Testing
import Foundation
@testable import SnapGrid

@Suite("Error Descriptions")
struct ErrorDescriptionTests {

    // MARK: - AIAnalysisService.AnalysisError

    @Test("AnalysisError.noAPIKey has description")
    func analysisNoAPIKey() {
        let error = AIAnalysisService.AnalysisError.noAPIKey
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("AnalysisError.imageConversionFailed has description")
    func analysisImageConversion() {
        let error = AIAnalysisService.AnalysisError.imageConversionFailed
        #expect(error.errorDescription != nil)
    }

    @Test("AnalysisError.invalidResponse has description")
    func analysisInvalidResponse() {
        let error = AIAnalysisService.AnalysisError.invalidResponse
        #expect(error.errorDescription != nil)
    }

    @Test("AnalysisError.apiError includes status code and message")
    func analysisApiError() {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 429, message: "Rate limited")
        let desc = error.errorDescription!
        #expect(desc.contains("429"))
        #expect(desc.contains("Rate limited"))
    }

    @Test("AnalysisError.parseFailed has description")
    func analysisParseFailed() {
        let error = AIAnalysisService.AnalysisError.parseFailed
        #expect(error.errorDescription != nil)
    }

    // MARK: - KeySyncCrypto.KeySyncError

    @Test("KeySyncError.unsupportedVersion has description")
    func keySyncUnsupportedVersion() {
        let error = KeySyncCrypto.KeySyncError.unsupportedVersion
        #expect(error.errorDescription != nil)
    }

    @Test("KeySyncError.corruptedData has description")
    func keySyncCorruptedData() {
        let error = KeySyncCrypto.KeySyncError.corruptedData
        #expect(error.errorDescription != nil)
    }

    // MARK: - TwitterVideoService.TwitterError

    @Test("TwitterError cases all have descriptions",
          arguments: [
            TwitterVideoService.TwitterError.invalidURL,
            .noMediaInTweet,
            .apiRequestFailed(502),
            .malformedResponse
          ])
    func twitterErrors(_ error: TwitterVideoService.TwitterError) {
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("TwitterError.apiRequestFailed includes status code")
    func twitterApiErrorCode() {
        let error = TwitterVideoService.TwitterError.apiRequestFailed(503)
        #expect(error.errorDescription!.contains("503"))
    }

    // MARK: - ModelDiscoveryService.DiscoveryError

    @Test("DiscoveryError.noAPIKey has description")
    func discoveryNoAPIKey() {
        let error = ModelDiscoveryService.DiscoveryError.noAPIKey
        #expect(error.errorDescription != nil)
    }

    @Test("DiscoveryError.apiError includes message")
    func discoveryApiError() {
        let error = ModelDiscoveryService.DiscoveryError.apiError("timeout")
        #expect(error.errorDescription!.contains("timeout"))
    }
}
