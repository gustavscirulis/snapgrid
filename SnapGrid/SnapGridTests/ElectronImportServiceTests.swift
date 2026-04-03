import Testing
import Foundation
@testable import SnapGrid

@Suite("ElectronImportService Helpers", .tags(.parsing))
@MainActor
struct ElectronImportServiceTests {

    // MARK: - parseDate

    @Test("Parses ISO 8601 date with fractional seconds")
    func parseDateFractional() {
        let date = ElectronImportService.parseDate("2024-03-15T10:30:45.123Z")
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        #expect(components.year == 2024)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    @Test("Parses ISO 8601 date without fractional seconds")
    func parseDateBasic() {
        let date = ElectronImportService.parseDate("2024-03-15T10:30:45Z")
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        #expect(components.year == 2024)
        #expect(components.month == 3)
    }

    @Test("Nil string returns current date")
    func parseDateNil() {
        let before = Date()
        let date = ElectronImportService.parseDate(nil)
        let after = Date()
        #expect(date >= before)
        #expect(date <= after)
    }

    @Test("Invalid string returns current date")
    func parseDateInvalid() {
        let before = Date()
        let date = ElectronImportService.parseDate("not-a-date")
        let after = Date()
        #expect(date >= before)
        #expect(date <= after)
    }

    // MARK: - extractId

    @Test("Extracts ID from standard JSON filename")
    func extractIdStandard() {
        let url = URL(fileURLWithPath: "/path/to/metadata/abc123.json")
        #expect(ElectronImportService.extractId(from: url) == "abc123")
    }

    @Test("Extracts ID from iCloud placeholder filename")
    func extractIdICloudPlaceholder() {
        let url = URL(fileURLWithPath: "/path/to/metadata/.abc123.json.icloud")
        #expect(ElectronImportService.extractId(from: url) == "abc123")
    }

    @Test("Handles UUID-style IDs")
    func extractIdUUID() {
        let url = URL(fileURLWithPath: "/path/to/img_1700000000_abc1234.json")
        #expect(ElectronImportService.extractId(from: url) == "img_1700000000_abc1234")
    }
}
