import SwiftUI

struct TransferProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TransferEngine.self) private var transfers
    @Environment(LibraryScanner.self) private var scanner

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let summary = transfers.summary {
                        SummaryView(summary: summary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: transfers.fractionCompleted)
                            Text("\(transfers.finishedCount) of \(transfers.jobs.count) · \(ByteFormatting.string(transfers.completedBytes)) of \(ByteFormatting.string(transfers.totalBytes))")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if transfers.isPausedForLowPower {
                                Label("Paused while Low Power Mode is on.", systemImage: "battery.25")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            if transfers.isWaitingToDelete {
                                Label("Confirm deleting the uploaded videos from your iPhone.", systemImage: "trash")
                                    .font(.footnote)
                            } else {
                                Text("You can leave the app; iOS keeps the move going and shows its progress.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Videos") {
                    ForEach(transfers.jobs) { job in
                        HStack(spacing: 12) {
                            AssetThumbnail(identifier: job.video.id, side: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.video.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? job.video.filename)
                                Text(job.state.label)
                                    .font(.caption)
                                    .foregroundStyle(color(for: job.state))
                                    .lineLimit(2)
                            }
                            Spacer()
                            stateIcon(job.state)
                        }
                    }
                }
            }
            .navigationTitle(transfers.isRunning ? "Moving Videos" : "Move Finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if transfers.isRunning {
                        Button("Stop", role: .destructive) { transfers.cancel() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(transfers.isRunning ? "Hide" : "Done") {
                        if !transfers.isRunning {
                            transfers.dismiss()
                            Task { await scanner.scan() }
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private func color(for state: TransferEngine.JobState) -> Color {
        switch state {
        case .moved: .green
        case .failed: .red
        case .keptOnPhone: .orange
        default: .secondary
        }
    }

    @ViewBuilder
    private func stateIcon(_ state: TransferEngine.JobState) -> some View {
        switch state {
        case .moved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .keptOnPhone: Image(systemName: "iphone.badge.exclamationmark").foregroundStyle(.orange)
        case .cancelled: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        default: ProgressView()
        }
    }
}

private struct SummaryView: View {
    let summary: TransferEngine.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.freedBytes > 0 {
                Text("You freed \(ByteFormatting.string(summary.freedBytes)) 🎉").font(.title2.bold())
            } else {
                Text("\(summary.movedCount) video\(summary.movedCount == 1 ? "" : "s") moved").font(.title2.bold())
            }
            if summary.keptCount > 0 {
                Text("\(summary.keptCount) uploaded but kept on your iPhone because the cloud copy couldn't be verified.")
                    .font(.subheadline).foregroundStyle(.orange)
            }
            if summary.failedCount > 0 {
                Text("\(summary.failedCount) couldn't be moved and are still on your iPhone.")
                    .font(.subheadline).foregroundStyle(.red)
            }
            if summary.deletionDeclined {
                Text("The videos are safe in your cloud, but weren't deleted from your iPhone because deletion wasn't confirmed.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if summary.deletedFromPhone {
                VStack(alignment: .leading, spacing: 6) {
                    Label("One more step to free the space", systemImage: "trash").font(.headline)
                    Text("iOS keeps deleted videos for 30 days. To free the space now, open Photos › Collections › Recently Deleted, tap Select, then Delete All.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Open Photos") {
                        if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
