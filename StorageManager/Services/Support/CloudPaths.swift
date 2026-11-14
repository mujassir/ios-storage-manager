import Foundation

/// Builds the folder layout and readable file names used in every cloud account:
/// `Storage Manager/Videos/2024/2024-07/2024-07-14 Beach in Santa Monica.mov`
nonisolated enum CloudPaths {
    static func folderPath(for date: Date?, calendar: Calendar = .current) -> String {
        guard let date else { return "Videos/Undated" }
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        return String(format: "Videos/%04d/%04d-%02d", year, year, month)
    }

    static func filename(title: String, date: Date?, originalFilename: String, calendar: Calendar = .current) -> String {
        let ext = (originalFilename as NSString).pathExtension.lowercased()
        let originalStem = (originalFilename as NSString).deletingPathExtension
        var stem = ""
        if let date {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            stem = String(format: "%04d-%02d-%02d %02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
        }
        let cleanTitle = sanitize(title)
        if !cleanTitle.isEmpty {
            stem = stem.isEmpty ? cleanTitle : "\(stem) \(cleanTitle)"
        }
        if stem.isEmpty { stem = sanitize(originalStem) }
        if stem.isEmpty { stem = "Video" }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// Removes characters that Drive, OneDrive or file systems reject, and caps the length.
    static func sanitize(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|#%").union(.controlCharacters).union(.newlines)
        let cleaned = text.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return String(trimmed.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    static func mimeType(forFilename filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mov": "video/quicktime"
        case "mp4", "m4v": "video/mp4"
        case "3gp": "video/3gpp"
        default: "application/octet-stream"
        }
    }

    /// Uniform type identifier string for AVFoundation's resource loader.
    static func uniformTypeIdentifier(forFilename filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mov": "com.apple.quicktime-movie"
        case "mp4": "public.mpeg-4"
        case "m4v": "com.apple.m4v-video"
        default: "public.movie"
        }
    }
}
