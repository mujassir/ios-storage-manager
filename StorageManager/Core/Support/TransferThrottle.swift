import Foundation

/// Pauses uploads between chunks while Low Power Mode is on (if the user wants that).
enum TransferThrottle {
    static let pauseOnLowPowerKey = "settings.pauseOnLowPower"

    static var shouldPause: Bool {
        SharedContainer.defaults.bool(forKey: pauseOnLowPowerKey) && ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func waitWhilePaused() async {
        while shouldPause && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
