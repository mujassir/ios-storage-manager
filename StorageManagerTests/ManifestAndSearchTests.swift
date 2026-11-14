import Testing
import Foundation
@testable import StorageManager

struct CatalogManifestTests {
    private func entry(_ id: UUID = UUID(), title: String = "Beach", createdAt: Date? = .now) -> CatalogManifest.Entry {
        CatalogManifest.Entry(
            catalogID: id, originalFilename: "IMG_1.MOV", title: title, placeName: "Santa Monica", keywords: "beach ocean",
            sizeBytes: 1_000, durationSeconds: 12, pixelWidth: 1920, pixelHeight: 1080, createdAt: createdAt,
            latitude: 34.0, longitude: -118.5, remoteFileID: "abc", remotePath: "Videos/2024/x.mov", checksum: "c", movedAt: .now
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let manifest = CatalogManifest(updatedAt: Date(timeIntervalSince1970: 1_700_000_000), entries: [entry(createdAt: Date(timeIntervalSince1970: 1_600_000_000))])
        let decoded = try CatalogManifest.decode(manifest.encoded())
        #expect(decoded.entries.map(\.catalogID) == manifest.entries.map(\.catalogID))
        #expect(decoded.entries.first?.createdAt == manifest.entries.first?.createdAt)
    }

    @Test func mergeReplacesAndAppends() {
        let id = UUID()
        let base = CatalogManifest(updatedAt: .now, entries: [entry(id, title: "Old")])
        let merged = base.merging([entry(id, title: "New"), entry()])
        #expect(merged.entries.count == 2)
        #expect(merged.entries.first { $0.catalogID == id }?.title == "New")
    }

    @Test func removeDropsEntries() {
        let keep = entry(), drop = entry()
        let manifest = CatalogManifest(updatedAt: .now, entries: [keep, drop]).removing(catalogIDs: [drop.catalogID])
        #expect(manifest.entries.map(\.catalogID) == [keep.catalogID])
    }
}

struct SearchCriteriaTests {
    private func matches(_ criteria: SearchCriteria, title: String = "Sunset Beach Walk", place: String = "Santa Monica",
                         keywords: String = "beach ocean", date: Date? = Date(timeIntervalSince1970: 1_720_000_000),
                         duration: Double = 120, provider: ProviderKind = .googleDrive) -> Bool {
        criteria.matches(title: title, placeName: place, keywords: keywords, filename: "IMG_1.MOV",
                         createdAt: date, durationSeconds: duration, provider: provider)
    }

    @Test func plainSearchRequiresAllWords() {
        #expect(matches(.plain("beach santa")))
        #expect(!matches(.plain("beach paris")))
        #expect(matches(.plain("")))
    }

    @Test func aiKeywordsAreAlternatives() {
        let criteria = SearchCriteria(keywords: ["paris", "ocean"], requireAllKeywords: false)
        #expect(matches(criteria))
    }

    @Test func dateDurationAndProviderFilters() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        #expect(matches(SearchCriteria(fromDate: date.addingTimeInterval(-86_400), toDate: date.addingTimeInterval(86_400))))
        #expect(!matches(SearchCriteria(fromDate: date.addingTimeInterval(86_400))))
        #expect(!matches(SearchCriteria(fromDate: date), date: nil))
        #expect(!matches(SearchCriteria(minimumDurationSeconds: 300)))
        #expect(!matches(SearchCriteria(provider: .oneDrive)))
    }
}

struct ProviderParsingTests {
    @Test func googleRangeHeader() {
        #expect(GoogleDriveProvider.nextOffset(fromRangeHeader: "bytes=0-1048575") == 1_048_576)
        #expect(GoogleDriveProvider.nextOffset(fromRangeHeader: nil) == 0)
    }

    @Test func oneDriveNextExpectedRanges() {
        #expect(OneDriveProvider.nextOffset(fromUploadSession: Data(#"{"nextExpectedRanges":["8192000-"]}"#.utf8)) == 8_192_000)
        #expect(OneDriveProvider.nextOffset(fromUploadSession: Data("{}".utf8)) == nil)
    }

    @Test func chunkSizesMeetProviderRules() {
        #expect(GoogleDriveProvider.chunkSize % (256 * 1024) == 0)
        #expect(OneDriveProvider.chunkSize % (320 * 1024) == 0)
        #expect(OneDriveProvider.chunkSize < 60 * 1024 * 1024)
    }
}

struct OAuthTests {
    /// RFC 7636 Appendix B example.
    @Test func pkceChallengeMatchesRFC() {
        #expect(OAuthClient.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func formEncodingEscapesReservedCharacters() {
        #expect(OAuthClient.formEncode(["redirect_uri": "msauth.app://auth", "scope": "a b"]) == "redirect_uri=msauth.app%3A%2F%2Fauth&scope=a%20b")
    }

    @Test func refreshKeepsPreviousRefreshToken() {
        let response = OAuthTokenResponse(access_token: "new", refresh_token: nil, expires_in: 3600)
        #expect(response.tokenSet(keepingRefreshToken: "old").refreshToken == "old")
    }
}
