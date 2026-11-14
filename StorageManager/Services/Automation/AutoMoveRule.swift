import Foundation

/// A Pro rule such as "screen recordings older than 30 days" or "videos over 1 GB".
nonisolated struct AutoMoveRule: Codable, Sendable, Identifiable, Equatable {
    enum Destination: Codable, Sendable, Hashable {
        case automatic
        case account(AccountKey)
    }

    var id = UUID()
    var name: String
    var isEnabled = true
    /// 0 means any size.
    var minimumSizeMB = 0
    /// 0 means any age.
    var olderThanDays = 0
    var onlyScreenRecordings = false
    var skipFavorites = true
    var destination: Destination = .automatic

    func matches(_ video: VideoAsset, now: Date = .now) -> Bool {
        guard isEnabled, video.isLocallyAvailable else { return false }
        if skipFavorites && video.isFavorite { return false }
        if onlyScreenRecordings && !video.isScreenRecording { return false }
        if minimumSizeMB > 0 && video.sizeBytes < Int64(minimumSizeMB) * 1024 * 1024 { return false }
        if olderThanDays > 0 {
            guard let created = video.creationDate,
                  let cutoff = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: now),
                  created < cutoff else { return false }
        }
        return true
    }

    var summary: String {
        var parts: [String] = [onlyScreenRecordings ? "Screen recordings" : "Videos"]
        if minimumSizeMB > 0 {
            parts.append(minimumSizeMB >= 1024 ? "over \(minimumSizeMB / 1024) GB" : "over \(minimumSizeMB) MB")
        }
        if olderThanDays > 0 { parts.append("older than \(olderThanDays) days") }
        if skipFavorites { parts.append("except favorites") }
        return parts.joined(separator: " ")
    }

    static let presets: [AutoMoveRule] = [
        AutoMoveRule(name: "Old screen recordings", olderThanDays: 30, onlyScreenRecordings: true),
        AutoMoveRule(name: "Large videos", minimumSizeMB: 1024),
        AutoMoveRule(name: "Videos older than a year", olderThanDays: 365),
    ]

    /// Videos matched by any enabled rule, grouped by the first matching rule's destination.
    /// Videos already in the cloud (`excluding`) are skipped.
    static func plan(_ rules: [AutoMoveRule], videos: [VideoAsset], excluding inCloud: Set<String>, now: Date = .now) -> [Destination: [VideoAsset]] {
        var plan: [Destination: [VideoAsset]] = [:]
        for video in videos where !inCloud.contains(video.id) {
            if let rule = rules.first(where: { $0.matches(video, now: now) }) {
                plan[rule.destination, default: []].append(video)
            }
        }
        return plan
    }
}
