import Foundation
import Vision
import MapKit
import FoundationModels
import Observation

/// What the app learned about a video before moving it. Everything is computed on the device.
nonisolated struct VideoInsight: Sendable, Equatable {
    var title: String
    var placeName: String
    var keywords: [String]
}

/// On-device understanding of videos:
/// - Vision classifies the thumbnail into scene labels ("beach", "dog", "concert").
/// - MapKit turns the GPS location into a place name.
/// - Apple Intelligence (Foundation Models) writes a short title from those facts.
/// Each step is optional; if Apple Intelligence is off or unsupported, a simple title is built from place and labels.
@Observable
final class VideoInsightService {
    var isAppleIntelligenceAvailable: Bool { SystemLanguageModel.default.isAvailable }

    var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            "On"
        case .unavailable(.deviceNotEligible):
            "Not supported on this iPhone"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in Settings"
        case .unavailable(.modelNotReady):
            "Downloading model…"
        case .unavailable:
            "Unavailable"
        }
    }

    func insight(thumbnailJPEG: Data?, latitude: Double?, longitude: Double?, date: Date?, durationSeconds: Double, useAI: Bool) async -> VideoInsight {
        async let labels = sceneLabels(for: thumbnailJPEG)
        async let place = placeName(latitude: latitude, longitude: longitude)
        let (keywords, placeName) = await (labels, place)

        var title = ""
        if useAI && isAppleIntelligenceAvailable {
            title = (try? await generateTitle(keywords: keywords, placeName: placeName, date: date, durationSeconds: durationSeconds)) ?? ""
        }
        if title.isEmpty {
            title = Self.fallbackTitle(keywords: keywords, placeName: placeName)
        }
        return VideoInsight(title: CloudPaths.sanitize(title), placeName: placeName, keywords: keywords)
    }

    // MARK: Vision

    private static let genericLabels: Set<String> = [
        "adult", "people", "person", "structure", "indoor", "outdoor", "material", "textile",
        "document", "screenshot", "wood_processed", "liquid", "water_body", "conveyance", "machine",
    ]

    func sceneLabels(for imageData: Data?) async -> [String] {
        guard let imageData else { return [] }
        let request = ClassifyImageRequest()
        guard let observations = try? await request.perform(on: imageData) else { return [] }
        return observations
            .filter { $0.confidence >= 0.35 && !Self.genericLabels.contains($0.identifier) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(6)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    // MARK: Place

    @ObservationIgnored private var placeCache: [String: String] = [:]

    func placeName(latitude: Double?, longitude: Double?) async -> String {
        guard let latitude, let longitude else { return "" }
        // Round to ~1 km so a batch of videos from the same place costs one lookup.
        let key = String(format: "%.2f,%.2f", latitude, longitude)
        if let cached = placeCache[key] { return cached }
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
              let item = try? await request.mapItems.first else { return "" }
        let name = item.addressRepresentations?.cityName ?? item.name ?? ""
        placeCache[key] = name
        return name
    }

    // MARK: Apple Intelligence

    private func generateTitle(keywords: [String], placeName: String, date: Date?, durationSeconds: Double) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You name home videos for a personal video library. \
            Write a short, warm, specific title of 2 to 5 words. \
            Never include the date, file names, or words like "video" or "clip". \
            Only use the facts provided; do not invent people or events.
            """)
        var facts: [String] = []
        if !keywords.isEmpty { facts.append("Scene: \(keywords.joined(separator: ", "))") }
        if !placeName.isEmpty { facts.append("Place: \(placeName)") }
        if let date { facts.append("Season and time: \(date.formatted(.dateTime.month(.wide).hour()))") }
        facts.append("Length: \(Int(durationSeconds)) seconds")
        let response = try await session.respond(to: facts.joined(separator: "\n"), generating: GeneratedVideoTitle.self)
        return response.content.title
    }

    static func fallbackTitle(keywords: [String], placeName: String) -> String {
        let label = keywords.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
        switch (label.isEmpty, placeName.isEmpty) {
        case (false, false): return "\(label) in \(placeName)"
        case (true, false): return placeName
        case (false, true): return label
        case (true, true): return ""
        }
    }
}

@Generable
nonisolated struct GeneratedVideoTitle {
    @Guide(description: "A short, friendly title of 2 to 5 words describing the video. No date.")
    var title: String
}
