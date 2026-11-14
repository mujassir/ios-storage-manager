import SwiftUI
import StoreKit

/// Native StoreKit paywall for Storage Manager Pro.
struct ProPaywallView: View {
    var reason: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SubscriptionStoreView(productIDs: ProStore.subscriptionIDs) {
                        VStack(spacing: 14) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 52))
                                .foregroundStyle(.tint)
                            Text("Storage Manager Pro").font(.title.bold())
                            if let reason {
                                Text(reason).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                feature("infinity", "Move any number of videos at once")
                                feature("moon.stars", "Auto-move rules run overnight while charging")
                                feature("bell.badge", "Get notified when space is ready to free")
                                feature("heart", "Support an app with no ads and no servers")
                            }
                        }
                        .padding()
                    }
                    .storeButton(.visible, for: .restorePurchases)
                    .subscriptionStoreControlStyle(.prominentPicker)
                    .frame(minHeight: 520)

                    VStack(spacing: 8) {
                        Text("Prefer to pay once?").font(.headline)
                        ProductView(id: ProStore.lifetimeID)
                            .productViewStyle(.compact)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { dismiss() }
                }
            }
            .onInAppPurchaseCompletion { _, result in
                if case .success(.success) = result {
                    await store.refreshEntitlements()
                    dismiss()
                }
            }
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
