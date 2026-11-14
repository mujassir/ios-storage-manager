import Foundation
import CloudKit

/// Whether the user's catalog can sync through iCloud.
enum ICloudStatus: Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable

    var message: String? {
        switch self {
        case .checking, .available: nil
        case .noAccount: "Sign in to iCloud in Settings so your cloud library is backed up and appears on your other devices. Until then it's saved on this iPhone and in each cloud account."
        case .restricted: "iCloud is restricted on this iPhone, so your cloud library is saved on this iPhone and in each cloud account only."
        case .temporarilyUnavailable: "iCloud is temporarily unavailable. Your library will sync when it's back."
        }
    }

    static func check() async -> ICloudStatus {
        guard let status = try? await CKContainer(identifier: AppConfig.cloudKitContainer).accountStatus() else {
            return .temporarilyUnavailable
        }
        switch status {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        default: return .temporarilyUnavailable
        }
    }
}
