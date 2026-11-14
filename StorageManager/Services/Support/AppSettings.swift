import Foundation
import Observation

/// User preferences, persisted in UserDefaults (per device; these are not synced).
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    var wifiOnly: Bool { didSet { defaults.set(wifiOnly, forKey: NetworkPolicy.wifiOnlyKey) } }
    var pauseOnLowPower: Bool { didSet { defaults.set(pauseOnLowPower, forKey: TransferThrottle.pauseOnLowPowerKey) } }
    var deleteAfterMove: Bool { didSet { defaults.set(deleteAfterMove, forKey: Keys.deleteAfterMove) } }
    var useAppleIntelligence: Bool { didSet { defaults.set(useAppleIntelligence, forKey: Keys.useAI) } }

    private enum Keys {
        static let onboarding = "settings.onboardingDone"
        static let deleteAfterMove = "settings.deleteAfterMove"
        static let useAI = "settings.useAppleIntelligence"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            NetworkPolicy.wifiOnlyKey: true,
            TransferThrottle.pauseOnLowPowerKey: true,
            Keys.deleteAfterMove: true,
            Keys.useAI: true,
        ])
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        wifiOnly = defaults.bool(forKey: NetworkPolicy.wifiOnlyKey)
        pauseOnLowPower = defaults.bool(forKey: TransferThrottle.pauseOnLowPowerKey)
        deleteAfterMove = defaults.bool(forKey: Keys.deleteAfterMove)
        useAppleIntelligence = defaults.bool(forKey: Keys.useAI)
    }
}

/// Pauses uploads between chunks while Low Power Mode is on (if the user wants that).
enum TransferThrottle {
    static let pauseOnLowPowerKey = "settings.pauseOnLowPower"

    static var shouldPause: Bool {
        UserDefaults.standard.bool(forKey: pauseOnLowPowerKey) && ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func waitWhilePaused() async {
        while shouldPause && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
