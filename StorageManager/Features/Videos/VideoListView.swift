import SwiftUI
import SwiftData

struct VideoListView: View {
    @Binding var selectedTab: AppTab

    @Environment(LibraryScanner.self) private var scanner
    @Environment(TransferEngine.self) private var transfers
    @AppStorage("videos.filter") private var filter: VideoFilter = .all

    @State private var selection = Set<String>()
    @State private var showMoveSheet = false
    @State private var showProgress = false

    private var visibleVideos: [VideoAsset] { scanner.videos.filter(filter.matches) }
    private var selectedVideos: [VideoAsset] { scanner.videos.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedVideos.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterChips
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    if visibleVideos.isEmpty {
                        ContentUnavailableView(
                            scanner.isScanning ? "Scanning…" : "No Videos",
                            systemImage: "video.slash",
                            description: Text(scanner.isScanning ? "Looking through your library." : "Nothing matches this filter.")
                        )
                    }
                    ForEach(visibleVideos) { video in
                        VideoRow(video: video, isSelected: selection.contains(video.id))
                            .contentShape(.rect)
                            .onTapGesture { toggle(video) }
                            .hoverEffect(.highlight)
                    }
                } header: {
                    Text("\(visibleVideos.count) videos · \(ByteFormatting.string(visibleVideos.reduce(0) { $0 + $1.sizeBytes }))")
                }
            }
            .navigationTitle("Videos")
            .refreshable { await scanner.scan() }
            .task { if scanner.lastScan == nil { await scanner.scan() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if transfers.hasActivity {
                        Button("Progress", systemImage: "arrow.up.circle") { showProgress = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allVisibleSelected ? "Deselect All" : "Select All") {
                        if allVisibleSelected {
                            selection.subtract(visibleVideos.map(\.id))
                        } else {
                            selection.formUnion(visibleVideos.map(\.id))
                        }
                    }
                    .disabled(visibleVideos.isEmpty)
                    .keyboardShortcut("a", modifiers: .command)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selection.isEmpty {
                    Button {
                        showMoveSheet = true
                    } label: {
                        Label("Move \(selection.count) · \(ByteFormatting.string(selectedBytes))", systemImage: "icloud.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(transfers.isRunning)
                    .keyboardShortcut("m", modifiers: .command)
                    .padding()
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                MoveSheet(videos: selectedVideos, selectedTab: $selectedTab) {
                    selection.removeAll()
                    showProgress = true
                }
            }
            .sheet(isPresented: $showProgress) {
                TransferProgressView()
            }
            .onChange(of: scanner.videos) {
                // Drop selections for videos that are gone (e.g. just moved).
                selection.formIntersection(scanner.videos.map(\.id))
            }
        }
    }

    private var allVisibleSelected: Bool {
        !visibleVideos.isEmpty && visibleVideos.allSatisfy { selection.contains($0.id) }
    }

    private func toggle(_ video: VideoAsset) {
        if selection.contains(video.id) { selection.remove(video.id) } else { selection.insert(video.id) }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(VideoFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            Text("\(option.title) \(scanner.count(matching: option))")
                                .font(.subheadline.weight(filter == option ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(filter == option ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct VideoRow: View {
    let video: VideoAsset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            AssetThumbnail(identifier: video.id)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? video.filename)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(DurationFormatting.string(video.durationSeconds))
                    if video.isScreenRecording { Image(systemName: "record.circle").accessibilityLabel("Screen recording") }
                    if video.isFavorite { Image(systemName: "heart.fill").accessibilityLabel("Favorite") }
                    if !video.isLocallyAvailable {
                        Label("iCloud only", systemImage: "icloud").labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteFormatting.string(video.sizeBytes))
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
