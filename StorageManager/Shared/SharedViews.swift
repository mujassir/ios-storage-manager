import SwiftUI
import AuthenticationServices

/// Thumbnail of a video still in the Photos library.
struct AssetThumbnail: View {
    @Environment(PhotoLibraryService.self) private var photos
    let identifier: String
    var side: CGFloat = 64

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "video").foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 10))
        .task(id: identifier) {
            image = await photos.thumbnail(for: identifier, size: CGSize(width: side * 3, height: side * 3))
        }
    }
}

/// Thumbnail stored in the catalog (works on a new device before any account is reconnected).
struct CatalogThumbnail: View {
    let data: Data?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProviderBadge: View {
    let provider: ProviderKind

    var body: some View {
        Image(systemName: provider.symbolName)
            .font(.caption2.weight(.semibold))
            .padding(5)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel(provider.displayName)
    }
}

/// Used / total bar for a phone or cloud account.
struct UsageBar: View {
    let used: Int64
    let total: Int64
    var tint: Color = .accentColor

    private var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(fraction > 0.9 ? Color.red : tint).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("\(ByteFormatting.string(used)) of \(ByteFormatting.string(total)) used")
    }
}

struct ErrorBanner: View {
    let message: String
    var systemImage = "exclamationmark.triangle.fill"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.15), in: .rect(cornerRadius: 12))
    }
}

extension WebAuthenticationSession {
    /// Adapts SwiftUI's web authentication session to the OAuth client.
    var presenter: WebAuthPresenter {
        { url, scheme in
            try await authenticate(using: url, callbackURLScheme: scheme)
        }
    }
}

extension Error {
    /// The user closed the sign-in sheet; not worth an alert.
    var isUserCancelledSignIn: Bool {
        (self as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }
}

extension Date {
    var monthYearTitle: String { formatted(.dateTime.month(.wide).year()) }
}
