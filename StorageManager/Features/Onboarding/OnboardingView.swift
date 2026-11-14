import SwiftUI
import Photos

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PhotoLibraryService.self) private var photos
    @State private var page = 0
    @State private var permissionDenied = false

    private struct Page {
        let symbol: String
        let title: String
        let text: String
    }

    private let pages = [
        Page(symbol: "internaldrive.fill", title: "Free up your iPhone",
             text: "See which videos take the most space, then move them to free cloud storage you already have, like Google Drive and OneDrive."),
        Page(symbol: "lock.shield.fill", title: "Your files, your cloud",
             text: "Videos go straight from your iPhone to your own cloud accounts. They never pass through our servers, and we can't see them."),
        Page(symbol: "play.rectangle.on.rectangle.fill", title: "Still yours to watch",
             text: "Browse moved videos in a familiar timeline, stream them anytime, and restore any video back to Photos with its original date."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 20) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 72))
                            .foregroundStyle(.tint)
                            .symbolEffect(.bounce, value: page)
                        Text(item.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(item.text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if permissionDenied {
                ErrorBanner(message: "Photos access is off. You can turn it on in Settings › Apps › Storage Manager › Photos.")
                    .padding(.horizontal)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    Task { await finish() }
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Allow Photos Access")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func finish() async {
        let status = await photos.requestAuthorization()
        if status == .authorized || status == .limited {
            settings.hasCompletedOnboarding = true
        } else {
            permissionDenied = true
        }
    }
}
