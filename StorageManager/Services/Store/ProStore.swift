import Foundation
import StoreKit
import Observation

/// Storage Manager Pro, sold with StoreKit 2: a monthly or yearly subscription, or a one-time lifetime unlock.
///
/// Free: everything in Phase 1, the Files app, widgets and share links; moves of up to `freeBatchLimit` videos at a time.
/// Pro: unlimited batch size and automatic moves (rules that run overnight while charging).
@Observable
final class ProStore {
    static let freeBatchLimit = 10

    static var monthlyID: String { "\(AppConfig.bundleID).pro.monthly" }
    static var yearlyID: String { "\(AppConfig.bundleID).pro.yearly" }
    static var lifetimeID: String { "\(AppConfig.bundleID).pro.lifetime" }
    static var subscriptionIDs: [String] { [monthlyID, yearlyID] }
    static var allProductIDs: Set<String> { [monthlyID, yearlyID, lifetimeID] }

    private(set) var isPro = false
    private(set) var hasLoaded = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            // Purchases made on another device, renewals, refunds and Ask to Buy approvals arrive here.
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await refreshEntitlements() }
    }

    func canMove(count: Int) -> Bool { isPro || count <= Self.freeBatchLimit }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  Self.allProductIDs.contains(transaction.productID) else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }
            pro = true
        }
        isPro = pro
        hasLoaded = true
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
