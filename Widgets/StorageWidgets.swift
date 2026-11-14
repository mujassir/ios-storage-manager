import WidgetKit
import SwiftUI

@main
struct StorageWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StorageWidget()
    }
}

struct StorageEntry: TimelineEntry {
    let date: Date
    let device: DeviceStorage
    let snapshot: LibrarySnapshot

    static let placeholder = StorageEntry(
        date: .now,
        device: DeviceStorage(totalBytes: 256_000_000_000, availableBytes: 38_000_000_000),
        snapshot: {
            var snapshot = LibrarySnapshot.empty
            snapshot.phone = .init(videoCount: 412, videoBytes: 61_000_000_000, reclaimableBytes: 54_000_000_000,
                                   pendingCleanupCount: 6, pendingCleanupBytes: 4_200_000_000, lastScan: .now)
            return snapshot
        }()
    )
}

struct StorageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StorageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        // The app reloads timelines after scans and moves; refresh hourly for free space changes.
        completion(Timeline(entries: [currentEntry()], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func currentEntry() -> StorageEntry {
        StorageEntry(date: .now, device: .current(), snapshot: LibrarySnapshot.load() ?? .empty)
    }
}

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StorageWidget", provider: StorageTimelineProvider()) { entry in
            StorageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Storage")
        .description("See free space on your iPhone and how much moving videos can free.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

enum WidgetLinks {
    static let storage = URL(string: "\(AppConfig.urlScheme)://storage")!
    static let cleanup = URL(string: "\(AppConfig.urlScheme)://cleanup")!
    static let largeVideos = URL(string: "\(AppConfig.urlScheme)://videos?filter=large")!
    static let library = URL(string: "\(AppConfig.urlScheme)://library")!
}

struct StorageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StorageEntry

    private var usedFraction: Double {
        entry.device.totalBytes > 0 ? Double(entry.device.usedBytes) / Double(entry.device.totalBytes) : 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: usedFraction) {
                Image(systemName: "internaldrive")
            } currentValueLabel: {
                Text(shortBytes(entry.device.availableBytes))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(WidgetLinks.storage)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("\(ByteFormatting.string(entry.device.availableBytes)) free").font(.headline)
                Text("\(ByteFormatting.string(entry.snapshot.phone.reclaimableBytes)) in videos can be freed")
                    .font(.caption)
            }
            .widgetURL(WidgetLinks.largeVideos)
        case .systemMedium:
            HStack(spacing: 16) {
                phoneSummary
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if entry.snapshot.phone.pendingCleanupCount > 0 {
                        Link(destination: WidgetLinks.cleanup) {
                            stat("Ready to free", ByteFormatting.string(entry.snapshot.phone.pendingCleanupBytes), symbol: "sparkles", tint: .green)
                        }
                    } else {
                        Link(destination: WidgetLinks.largeVideos) {
                            stat("Can be freed", ByteFormatting.string(entry.snapshot.phone.reclaimableBytes), symbol: "video", tint: .orange)
                        }
                    }
                    Link(destination: WidgetLinks.library) {
                        stat("In your clouds", "\(entry.snapshot.videos.count) videos", symbol: "cloud", tint: .blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            phoneSummary.widgetURL(WidgetLinks.storage)
        }
    }

    private var phoneSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("iPhone", systemImage: "iphone").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(ByteFormatting.string(entry.device.availableBytes))
                .font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text("free").font(.caption).foregroundStyle(.secondary)
            Gauge(value: usedFraction) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(usedFraction > 0.9 ? .red : .accentColor)
            Spacer(minLength: 0)
            Text("\(ByteFormatting.string(entry.snapshot.phone.videoBytes)) in videos")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ title: String, _ value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func shortBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 10 ? "\(Int(gb))G" : String(format: "%.1fG", gb)
    }
}
