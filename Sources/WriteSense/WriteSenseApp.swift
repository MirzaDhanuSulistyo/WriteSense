import AppKit
import SwiftUI

@main
struct WriteSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            StatusLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .defaultSize(width: 540, height: 600)

        Window("Writing Insights", id: "insights") {
            InsightsView()
                .environmentObject(model)
        }
        .defaultSize(width: 620, height: 560)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct StatusLabel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "pencil.and.outline")
            Circle()
                .fill(model.permissionTrusted && model.isLearningActive ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
        }
    }
}

struct MenuView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WriteSense")
                        .font(.title2.weight(.bold))
                    Text("Your writing, improved by your own habits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            StatusCard()

            if !model.permissionTrusted {
                PermissionCard()
            }

            Toggle(isOn: Binding(
                get: { model.isLearningActive },
                set: { model.setLearningActive($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isLearningActive ? "Learning active" : "Learning paused")
                        .font(.headline)
                    Text("Only approved, non-secure text fields are considered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            VStack(spacing: 8) {
                Button {
                    model.reviewCurrentParagraph()
                } label: {
                    Label("Review current paragraph", systemImage: "text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.permissionTrusted)

                Button {
                    model.deepReviewCurrentParagraph()
                } label: {
                    HStack {
                        if model.isDeepReviewing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "apple.intelligence")
                        }
                        Text(model.isDeepReviewing ? "Deep Reviewing…" : "Deep Review on this Mac")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canUseDeepReview)

                if !model.onDeviceModelStatus.isAvailable {
                    HStack(spacing: 6) {
                        Text(model.onDeviceModelStatus.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.onDeviceModelStatus == .appleIntelligenceNotEnabled {
                            Button("Enable") {
                                model.openAppleIntelligenceSettings()
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        openWindow(id: "insights")
                    } label: {
                        Label("Insights", systemImage: "chart.bar.xaxis")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if model.canUndo {
                        Button {
                            model.undoLastChange()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if !model.latestSuggestions.isEmpty {
                Divider()
                HStack {
                    Text("Suggestions")
                        .font(.headline)
                    Spacer()
                    Text(model.lastReviewLanguage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.latestSuggestions) { suggestion in
                            SuggestionCard(suggestion: suggestion)
                        }
                    }
                }
                .frame(minHeight: 150, maxHeight: 310)
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: 390)
        .onAppear {
            model.refreshPermission()
            model.refreshOnDeviceModelStatus()
        }
    }
}

struct StatusCard: View {
    @EnvironmentObject private var model: AppModel

    private var statusColor: Color {
        if !model.permissionTrusted { return .orange }
        if !model.isLearningActive { return .secondary }
        if !model.activeApplicationIsApproved { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusMessage)
                    .font(.subheadline.weight(.semibold))
                Text(model.currentApplicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("LOCAL")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.green.opacity(0.12), in: Capsule())
        }
        .padding(11)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PermissionCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission needed", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text("WriteSense uses macOS Accessibility APIs to read approved text fields. It never records raw keystrokes or secure fields.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Grant permission") {
                model.requestAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SuggestionCard: View {
    @EnvironmentObject private var model: AppModel
    let suggestion: Suggestion
    @State private var replacement: String

    init(suggestion: Suggestion) {
        self.suggestion = suggestion
        _replacement = State(initialValue: suggestion.suggestedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(suggestion.category.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if suggestion.isPersonalized {
                    Label("Personalized", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.1), in: Capsule())
                }
                Spacer()
                Text("\(Int(suggestion.confidence * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if suggestion.requiresClarification {
                Label("Choose your intended meaning", systemImage: "questionmark.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(suggestion.originalText)
                        .foregroundStyle(.red)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Replacement", text: $replacement)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(suggestion.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let reason = suggestion.personalizationReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if suggestion.requiresClarification {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suggestion.alternativeTexts, id: \.self) { alternative in
                        Button(alternative) {
                            if model.canApplyCurrentSuggestions {
                                model.editAndApply(suggestion, replacement: alternative)
                            } else {
                                model.copyReplacement(alternative)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Ignore") { model.ignore(suggestion) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else {
                HStack {
                    Button(model.canApplyCurrentSuggestions ? "Apply" : "Copy") {
                        if !model.canApplyCurrentSuggestions {
                            model.copyReplacement(replacement)
                        } else if replacement == suggestion.suggestedText {
                            model.accept(suggestion)
                        } else {
                            model.editAndApply(suggestion, replacement: replacement)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reject") {
                        model.reject(suggestion)
                    }
                    .buttonStyle(.bordered)
                    Button("Ignore") {
                        model.ignore(suggestion)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(11)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                HStack {
                    Label(model.permissionTrusted ? "Accessibility enabled" : "Accessibility required", systemImage: model.permissionTrusted ? "checkmark.shield" : "exclamationmark.shield")
                    Spacer()
                    Button(model.permissionTrusted ? "Open Settings" : "Grant access") {
                        model.requestAccessibilityPermission()
                    }
                }
                Toggle("Learning active", isOn: Binding(
                    get: { model.isLearningActive },
                    set: { model.setLearningActive($0) }
                ))
            } header: {
                Text("Privacy status")
            } footer: {
                Text("Text is analyzed locally. WriteSense stores temporary paragraph snapshots only while learning, then keeps compact correction patterns instead of full documents.")
            }

            Section {
                HStack {
                    Label(model.onDeviceModelStatus.title, systemImage: "apple.intelligence")
                    Spacer()
                    if model.onDeviceModelStatus == .appleIntelligenceNotEnabled {
                        Button("Enable") {
                            model.openAppleIntelligenceSettings()
                        }
                    } else {
                        Button("Refresh") {
                            model.refreshOnDeviceModelStatus()
                        }
                    }
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Deep Review uses Apple Foundation Models entirely on-device. No paragraph or API key is sent to a server.")
            }

            Section("Approved applications") {
                ForEach(SupportedApplication.defaults) { application in
                    Toggle(isOn: Binding(
                        get: { model.isApproved(application) },
                        set: { _ in model.toggleApplication(application) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(application.name, systemImage: "app")
                            if application.isSuggestionOnly {
                                Text("Suggestions and Copy only — off by default")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            } else if application.isSensitiveByDefault {
                                Text("Sensitive app — off by default")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Button {
                    model.addFrontmostApplication()
                } label: {
                    Label("Add current application", systemImage: "plus")
                }
            }

            Section("Your writing profile") {
                LabeledContent("Reliable patterns", value: "\(model.reliablePatternCount)")
                LabeledContent("Vocabulary entries", value: "\(model.profile.vocabulary.count)")
                LabeledContent("Suggestions accepted", value: "\(model.profile.acceptedSuggestionCount)")
                Button("Open writing insights") {
                    openWindow(id: "insights")
                }
            }

            Section("Data controls") {
                Button("Delete temporary data") {
                    model.deleteTodayData()
                }
                Button("Delete all learned data", role: .destructive) {
                    model.deleteAllData()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 600)
        .padding(.top, 8)
        .onAppear {
            model.refreshPermission()
            model.refreshOnDeviceModelStatus()
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Writing insights")
                        .font(.largeTitle.weight(.bold))
                    Text("A private view of the habits WriteSense has learned from your edits.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    InsightMetric(title: "Reliable patterns", value: "\(model.reliablePatternCount)", icon: "brain.head.profile")
                    InsightMetric(title: "Accepted", value: "\(model.profile.acceptedSuggestionCount)", icon: "checkmark.circle")
                    InsightMetric(title: "Vocabulary", value: "\(model.profile.vocabulary.count)", icon: "character.book.closed")
                }

                if model.learnedPatterns.isEmpty {
                    ContentUnavailableView(
                        "Your profile is still learning",
                        systemImage: "wand.and.stars",
                        description: Text("Make a few edits in an approved app. Repeated changes will appear here as patterns.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Learned patterns")
                            .font(.title3.weight(.semibold))
                        ForEach(model.learnedPatterns) { pattern in
                            PatternRow(pattern: pattern)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct InsightMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct PatternRow: View {
    @EnvironmentObject private var model: AppModel
    let pattern: LearnedPattern

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pattern.isReliable ? "checkmark.seal.fill" : "circle.dashed")
                .foregroundStyle(pattern.isReliable ? .green : .secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(pattern.category.title)
                        .font(.headline)
                    Text("\(pattern.occurrenceCount) observations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(pattern.description)
                    .font(.subheadline)
                Text("\(pattern.exampleBefore)  →  \(pattern.exampleAfter)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Menu {
                Button(pattern.enabled ? "Disable" : "Enable") {
                    model.togglePattern(pattern)
                }
                Button("Delete", role: .destructive) {
                    model.deletePattern(pattern)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(13)
        .background(.background, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(.quaternary)
        }
    }
}
