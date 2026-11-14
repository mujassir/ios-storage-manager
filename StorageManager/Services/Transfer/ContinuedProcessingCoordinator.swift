import Foundation
import BackgroundTasks

/// Keeps a move running after the user leaves the app, using iOS 26's `BGContinuedProcessingTask`.
/// The system shows its own progress UI (Live Activity style) and lets the user cancel from there.
/// If the system declines the request, moves still work while the app is open.
final class ContinuedProcessingCoordinator {
    private var task: BGContinuedProcessingTask?
    private var isActive = false
    private var title = ""
    private var onExpire: (() -> Void)?

    init() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: AppConfig.moveTaskIdentifier, using: .main) { @Sendable [weak self] task in
            let box = UncheckedSendableBox(task)
            MainActor.assumeIsolated { self?.attach(box.value) }
        }
    }

    func begin(title: String, subtitle: String, onExpire: @escaping () -> Void) {
        self.title = title
        self.onExpire = onExpire
        isActive = true
        let request = BGContinuedProcessingTaskRequest(identifier: AppConfig.moveTaskIdentifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not fatal: the move continues while the app is in the foreground.
        }
    }

    func update(fractionCompleted: Double, subtitle: String) {
        guard let task else { return }
        task.progress.completedUnitCount = Int64(min(max(fractionCompleted, 0), 1) * Double(task.progress.totalUnitCount))
        task.updateTitle(title, subtitle: subtitle)
    }

    func finish(success: Bool) {
        isActive = false
        onExpire = nil
        task?.setTaskCompleted(success: success)
        task = nil
    }

    private func attach(_ task: BGTask) {
        guard let continued = task as? BGContinuedProcessingTask, isActive else {
            task.setTaskCompleted(success: true)
            return
        }
        continued.progress.totalUnitCount = 1000
        continued.expirationHandler = { @Sendable [weak self] in
            Task { @MainActor in
                self?.onExpire?()
                self?.finish(success: false)
            }
        }
        self.task = continued
    }
}
