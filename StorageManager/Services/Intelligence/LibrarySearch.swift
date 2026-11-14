import Foundation
import FoundationModels
import Observation

/// What to look for in the cloud library.
nonisolated struct SearchCriteria: Sendable, Equatable {
    var keywords: [String] = []
    var fromDate: Date?
    var toDate: Date?
    var minimumDurationSeconds: Double = 0
    var provider: ProviderKind?
    /// Plain search requires every word; AI search keywords are alternatives ("beach" or "ocean").
    var requireAllKeywords = true

    var isEmpty: Bool { keywords.isEmpty && fromDate == nil && toDate == nil && minimumDurationSeconds == 0 && provider == nil }

    func matches(title: String, placeName: String, keywords videoKeywords: String, filename: String,
                 createdAt: Date?, durationSeconds: Double, provider videoProvider: ProviderKind) -> Bool {
        if let provider, provider != videoProvider { return false }
        if durationSeconds < minimumDurationSeconds { return false }
        if let fromDate {
            guard let createdAt, createdAt >= fromDate else { return false }
        }
        if let toDate {
            guard let createdAt, createdAt <= toDate else { return false }
        }
        guard !keywords.isEmpty else { return true }
        let haystack = [title, placeName, videoKeywords, filename].joined(separator: " ").lowercased()
        let hits = keywords.map { haystack.contains($0.lowercased()) }
        return requireAllKeywords ? hits.allSatisfy { $0 } : hits.contains(true)
    }

    /// Plain text search: every word must appear.
    static func plain(_ text: String) -> SearchCriteria {
        SearchCriteria(keywords: text.split(whereSeparator: { $0.isWhitespace }).map(String.init), requireAllKeywords: true)
    }
}

/// Turns "long beach videos from last summer on OneDrive" into structured criteria using the on-device model.
@Observable
final class LibrarySearchInterpreter {
    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func criteria(for query: String, now: Date = .now) async -> SearchCriteria {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchCriteria() }
        guard isAvailable else { return .plain(trimmed) }
        do {
            let session = LanguageModelSession(instructions: """
                You convert a search request for a personal video library into filters. \
                Today is \(Self.dayFormatter.string(from: now)). \
                Resolve relative dates such as "last summer" or "in March" into exact dates. \
                Keywords describe what is in the video or where it was filmed; include close synonyms.
                """)
            let filter = try await session.respond(to: trimmed, generating: GeneratedSearchFilter.self).content
            var criteria = SearchCriteria(
                keywords: filter.keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                fromDate: Self.dayFormatter.date(from: filter.fromDate),
                toDate: Self.dayFormatter.date(from: filter.toDate).map { Calendar.current.date(byAdding: .day, value: 1, to: $0) ?? $0 },
                minimumDurationSeconds: Double(max(0, filter.minimumDurationSeconds)),
                provider: ProviderKind(rawValue: filter.provider),
                requireAllKeywords: false
            )
            if criteria.isEmpty { criteria = .plain(trimmed) }
            return criteria
        } catch {
            return .plain(trimmed)
        }
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

@Generable
nonisolated struct GeneratedSearchFilter {
    @Guide(description: "Things or places to look for, e.g. beach, dog, birthday, Paris. Empty list if none.")
    var keywords: [String]
    @Guide(description: "Earliest capture date as YYYY-MM-DD, or an empty string if no date was mentioned.")
    var fromDate: String
    @Guide(description: "Latest capture date as YYYY-MM-DD, or an empty string if no date was mentioned.")
    var toDate: String
    @Guide(description: "Minimum length in seconds if the user asked for long videos (e.g. 300), otherwise 0.")
    var minimumDurationSeconds: Int
    @Guide(description: "Exactly googleDrive or oneDrive if the user named that service, otherwise an empty string.")
    var provider: String
}
