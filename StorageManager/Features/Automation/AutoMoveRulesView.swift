import SwiftUI
import SwiftData

/// List and edit auto-move rules (Pro).
struct AutoMoveRulesView: View {
    @Environment(AutoMoveService.self) private var autoMove
    @Environment(ProStore.self) private var store
    @State private var editing: AutoMoveRule?
    @State private var showPaywall = false

    var body: some View {
        List {
            if !store.isPro {
                Section {
                    Label("Auto-move rules are part of Storage Manager Pro.", systemImage: "lock")
                    Button("See Pro") { showPaywall = true }
                }
            }
            Section {
                if autoMove.rules.isEmpty {
                    Text("No rules yet. Start from a suggestion below.").foregroundStyle(.secondary)
                }
                ForEach(autoMove.rules) { rule in
                    Button {
                        editing = rule
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).foregroundStyle(.primary)
                                Text(rule.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !rule.isEnabled { Text("Off").foregroundStyle(.secondary) }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { autoMove.delete(autoMove.rules[index]) }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Matching videos upload overnight while your iPhone is charging and online. They stay on your iPhone until you tap Free on the Storage tab, because iOS asks you to confirm deletions.")
            }

            Section("Suggestions") {
                ForEach(AutoMoveRule.presets) { preset in
                    Button {
                        var rule = preset
                        rule.id = UUID()
                        editing = rule
                    } label: {
                        Label(preset.name, systemImage: "plus.circle")
                    }
                }
            }

            if let message = autoMove.lastRunMessage, let lastRun = autoMove.lastRun {
                Section("Last Run") {
                    LabeledContent(lastRun.formatted(date: .abbreviated, time: .shortened), value: message)
                }
            }
        }
        .navigationTitle("Auto-Move")
        .sheet(item: $editing) { rule in
            AutoMoveRuleEditor(rule: rule)
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(reason: "Let Storage Manager move videos for you.")
        }
    }
}

struct AutoMoveRuleEditor: View {
    @State var rule: AutoMoveRule

    @Environment(\.dismiss) private var dismiss
    @Environment(AutoMoveService.self) private var autoMove
    @Environment(AccountManager.self) private var accounts
    @Environment(ProStore.self) private var store
    @Query(sort: \LinkedAccount.linkedAt) private var linkedAccounts: [LinkedAccount]
    @State private var showPaywall = false

    private let sizeOptions = [0, 100, 500, 1024, 2048, 5120]
    private let ageOptions = [0, 7, 30, 90, 180, 365]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $rule.name)
                    Toggle("Enabled", isOn: $rule.isEnabled)
                }
                Section("Which videos") {
                    Picker("Larger than", selection: $rule.minimumSizeMB) {
                        ForEach(sizeOptions, id: \.self) { mb in
                            Text(mb == 0 ? "Any size" : mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB").tag(mb)
                        }
                    }
                    Picker("Older than", selection: $rule.olderThanDays) {
                        ForEach(ageOptions, id: \.self) { days in
                            Text(days == 0 ? "Any age" : "\(days) days").tag(days)
                        }
                    }
                    Toggle("Only screen recordings", isOn: $rule.onlyScreenRecordings)
                    Toggle("Skip favorites", isOn: $rule.skipFavorites)
                }
                Section("Move to") {
                    Picker("Destination", selection: $rule.destination) {
                        Text("Automatic").tag(AutoMoveRule.Destination.automatic)
                        ForEach(linkedAccounts.filter(accounts.isConnected)) { account in
                            Text("\(account.provider.displayName) · \(account.email)")
                                .tag(AutoMoveRule.Destination.account(account.accountKey))
                        }
                    }
                }
                Section {
                    Text(rule.summary).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(rule.name.isEmpty ? "New Rule" : rule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        guard store.isPro else {
                            showPaywall = true
                            return
                        }
                        if rule.name.trimmingCharacters(in: .whitespaces).isEmpty { rule.name = rule.summary }
                        autoMove.save(rule)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView(reason: "Auto-move rules are part of Pro.")
            }
        }
    }
}
