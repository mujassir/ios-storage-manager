import SwiftUI
import SwiftData

/// Photos-style timeline of everything that was moved to the cloud.
struct LibraryView: View {
    @Binding var selectedTab: AppTab

    @Environment(\.modelContext) private var context
    @Environment(LibrarySearchInterpreter.self) private var interpreter
    @Environment(AppSettings.self) private var settings
    @Environment(RestoreService.self) private var restores
    @Query(sort: \MovedVideo.createdAt, order: .reverse) private var videos: [MovedVideo]

    @State private var searchText = ""
    @State private var criteria = SearchCriteria()
    @State private var isInterpreting = false
    @State private var providerFilter: ProviderKind?
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var showRestoreOptions = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    private var filtered: [MovedVideo] {
        videos.filter { video in
            if let providerFilter, video.provider != providerFilter { return false }
            return criteria.matches(
                title: video.title, placeName: video.placeName, keywords: video.keywords,
                filename: video.originalFilename, createdAt: video.createdAt,
                durationSeconds: video.durationSeconds, provider: video.provider
            )
        }
    }

    private struct MonthSection: Identifiable {
        let title: String
        let videos: [MovedVideo]
        var id: String { title }
    }

    private var sections: [MonthSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { video -> Date in
            video.createdAt.flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? .distantPast
        }
        return groups.keys.sorted(by: >).map { month in
            MonthSection(title: month == .distantPast ? "Undated" : month.monthYearTitle, videos: groups[month] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if videos.isEmpty {
                    ContentUnavailableView(
                        "No Videos in the Cloud Yet",
                        systemImage: "icloud.and.arrow.up",
                        description: Text("Videos you move will appear here, ready to stream or restore.")
                    )
                    .padding(.top, 80)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 80)
                } else {
                    if !criteria.isEmpty && !criteria.requireAllKeywords {
                        aiCriteriaSummary
                    }
                    LazyVGrid(columns: columns, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.videos) { video in
                                    cell(for: video)
                                }
                            } header: {
                                Text(section.title)
                                    .font(.headline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .glassEffect(.regular, in: .capsule)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: MovedVideo.self) { video in
                CloudVideoDetailView(video: video, selectedTab: $selectedTab)
            }
            .searchable(text: $searchText, prompt: interpreter.isAvailable && settings.useAppleIntelligence
                        ? "Try “beach videos from last summer”" : "Search titles and places")
            .onChange(of: searchText) { _, text in
                // Live plain search while typing; Apple Intelligence runs on submit.
                criteria = .plain(text)
            }
            .onSubmit(of: .search) { Task { await interpret() } }
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selection.isEmpty {
                    Button {
                        showRestoreOptions = true
                    } label: {
                        Label("Restore \(selection.count) to Photos", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(restores.isBusy)
                    .padding()
                }
            }
            .confirmationDialog("Restore to Photos", isPresented: $showRestoreOptions, titleVisibility: .visible) {
                Button("Restore and Keep Cloud Copy") { restoreSelection(deleteCloudCopy: false) }
                Button("Restore and Remove from Cloud", role: .destructive) { restoreSelection(deleteCloudCopy: true) }
            } message: {
                Text("Videos are saved back to Photos at their original date and place.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isInterpreting { ProgressView() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Cloud", selection: $providerFilter) {
                    Text("All Clouds").tag(ProviderKind?.none)
                    ForEach(ProviderKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName).tag(ProviderKind?.some(kind))
                    }
                }
            } label: {
                Image(systemName: providerFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelecting ? "Done" : "Select") {
                isSelecting.toggle()
                selection.removeAll()
            }
            .disabled(videos.isEmpty)
        }
    }

    @ViewBuilder
    private func cell(for video: MovedVideo) -> some View {
        let content = ZStack(alignment: .bottomLeading) {
            CatalogThumbnail(data: video.thumbnailJPEG)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            HStack {
                Text(DurationFormatting.string(video.durationSeconds))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                ProviderBadge(provider: video.provider)
            }
            .padding(4)
            if isSelecting {
                Image(systemName: selection.contains(video.catalogID) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(.white, Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
            if let state = restores.states[video.catalogID], state == .downloading || state == .saving {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.3))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(video.displayTitle), \(video.createdAt?.formatted(date: .long, time: .omitted) ?? ""), \(DurationFormatting.string(video.durationSeconds))")

        if isSelecting {
            content
                .onTapGesture {
                    if selection.contains(video.catalogID) { selection.remove(video.catalogID) } else { selection.insert(video.catalogID) }
                }
                .accessibilityAddTraits(selection.contains(video.catalogID) ? [.isButton, .isSelected] : .isButton)
        } else {
            NavigationLink(value: video) { content }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .contextMenu {
                    Button("Restore to Photos", systemImage: "square.and.arrow.down") {
                        Task { await restores.restore([video], deleteCloudCopy: false, context: context) }
                    }
                    if let url = video.shareURL {
                        ShareLink(item: url) { Label("Share Link", systemImage: "link") }
                    }
                }
        }
    }

    private var aiCriteriaSummary: some View {
        var parts: [String] = []
        if !criteria.keywords.isEmpty { parts.append(criteria.keywords.joined(separator: ", ")) }
        if let from = criteria.fromDate { parts.append("from \(from.formatted(date: .abbreviated, time: .omitted))") }
        if let to = criteria.toDate { parts.append("to \(to.formatted(date: .abbreviated, time: .omitted))") }
        if criteria.minimumDurationSeconds > 0 { parts.append("over \(DurationFormatting.string(criteria.minimumDurationSeconds))") }
        if let provider = criteria.provider { parts.append("on \(provider.displayName)") }
        return Label(parts.joined(separator: " · "), systemImage: "apple.intelligence")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 6)
    }

    private func interpret() async {
        guard settings.useAppleIntelligence, interpreter.isAvailable else {
            criteria = .plain(searchText)
            return
        }
        isInterpreting = true
        criteria = await interpreter.criteria(for: searchText)
        isInterpreting = false
    }

    private func restoreSelection(deleteCloudCopy: Bool) {
        let chosen = videos.filter { selection.contains($0.catalogID) }
        selection.removeAll()
        isSelecting = false
        Task { await restores.restore(chosen, deleteCloudCopy: deleteCloudCopy, context: context) }
    }
}
