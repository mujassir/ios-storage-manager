import Testing
import Foundation
@testable import StorageManager

struct CloudPathsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var july14: Date {
        calendar.date(from: DateComponents(year: 2024, month: 7, day: 14, hour: 16, minute: 5))!
    }

    @Test func folderUsesYearAndMonth() {
        #expect(CloudPaths.folderPath(for: july14, calendar: calendar) == "Videos/2024/2024-07")
        #expect(CloudPaths.folderPath(for: nil, calendar: calendar) == "Videos/Undated")
    }

    @Test func filenameCombinesDateAndTitle() {
        let name = CloudPaths.filename(title: "Beach in Santa Monica", date: july14, originalFilename: "IMG_1234.MOV", calendar: calendar)
        #expect(name == "2024-07-14 16.05 Beach in Santa Monica.mov")
    }

    @Test func filenameFallsBackToOriginal() {
        #expect(CloudPaths.filename(title: "", date: nil, originalFilename: "IMG_1234.MOV", calendar: calendar) == "IMG_1234.mov")
        #expect(CloudPaths.filename(title: "", date: nil, originalFilename: "", calendar: calendar) == "Video")
    }

    @Test func sanitizeRemovesForbiddenCharacters() {
        #expect(CloudPaths.sanitize("  Mom's \"party\": 50% / fun?  ") == "Mom's party 50 fun")
        #expect(CloudPaths.sanitize("...") == "")
        #expect(CloudPaths.sanitize(String(repeating: "a", count: 200)).count == 80)
    }

    @Test func mimeTypes() {
        #expect(CloudPaths.mimeType(forFilename: "a.MOV") == "video/quicktime")
        #expect(CloudPaths.mimeType(forFilename: "a.mp4") == "video/mp4")
        #expect(CloudPaths.uniformTypeIdentifier(forFilename: "x.mov") == "com.apple.quicktime-movie")
    }
}
