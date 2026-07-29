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

        Window("Welcome to WriteSense", id: "onboarding") {
            OnboardingView()
                .environmentObject(model)
        }
        .defaultSize(width: 620, height: 520)

        Window("Beta Diagnostics", id: "diagnostics") {
            DiagnosticsView()
                .environmentObject(model)
        }
        .defaultSize(width: 680, height: 600)

        Window("Beta Feedback", id: "feedback") {
            BetaFeedbackView()
                .environmentObject(model)
        }
        .defaultSize(width: 620, height: 650)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct StatusLabel: View {
    @EnvironmentObject private var model: AppModel

    private var isActivelyLearning: Bool {
        model.permissionTrusted && model.storageAvailable &&
            model.isLearningActive && model.activeApplicationIsApproved
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isActivelyLearning ? "pencil.and.outline" : "pause.circle")
            Circle()
                .fill(isActivelyLearning ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
        }
        .accessibilityLabel(model.statusMessage)
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

            if !model.onboardingCompleted {
                OnboardingCard()
            }

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
            .disabled(!model.storageAvailable)

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

struct OnboardingCard: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Private by design", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
            Text("WriteSense reads paragraph snapshots only in apps you approve. It blocks secure fields, never records raw keystrokes, and encrypts learned data with a key stored in your Mac’s Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("I send it yesterday")
                    .strikethrough()
                Image(systemName: "arrow.right")
                Text("I sent it yesterday")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text("After repeated edits, WriteSense can prioritize similar tense corrections and explain why.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Open setup guide") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
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
    @State private var confirmDeleteAll = false

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
                .disabled(!model.storageAvailable)
                if !model.storageAvailable {
                    Label("Encrypted storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.red)
                }
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

            Section {
                Toggle("Sentence capitalization", isOn: Binding(
                    get: { model.capitalizationChecksEnabled },
                    set: { model.setCapitalizationChecksEnabled($0) }
                ))
                Picker("Writing preference", selection: Binding(
                    get: { model.tonePreference },
                    set: { model.setTonePreference($0) }
                )) {
                    ForEach(TonePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
            } header: {
                Text("Writing checks")
            } footer: {
                Text("Writing preference affects ranking while preserving your meaning and personal vocabulary.")
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
                if !model.customApprovedApplications.isEmpty {
                    Divider()
                    ForEach(model.customApprovedApplications) { application in
                        HStack {
                            Label(application.name, systemImage: "app.badge.checkmark")
                            Spacer()
                            Button("Remove", role: .destructive) {
                                model.removeCustomApplication(application)
                            }
                            .buttonStyle(.borderless)
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
                LabeledContent("Suggestions rejected", value: "\(model.profile.rejectedSuggestionCount)")
                Button("Open writing insights") {
                    openWindow(id: "insights")
                }
                Button("Reset personalization", role: .destructive) {
                    model.resetPersonalization()
                }
            }

            Section {
                Toggle("Content-free local diagnostics", isOn: Binding(
                    get: { model.diagnosticsEnabled },
                    set: { model.setDiagnosticsEnabled($0) }
                ))
                HStack {
                    Button {
                        model.runCompatibilityCheck()
                    } label: {
                        Label("Check last active app", systemImage: "checkmark.shield")
                    }
                    Spacer()
                    if let observation = model.latestCompatibilityObservation {
                        Text(observation.result.title)
                            .font(.caption)
                            .foregroundStyle(observation.result.isSuccessfulSafetyResult ? .green : .orange)
                    }
                }
                Button {
                    openWindow(id: "diagnostics")
                } label: {
                    Label("Open beta diagnostics", systemImage: "stethoscope")
                }
                Button {
                    openWindow(id: "feedback")
                } label: {
                    Label("Provide beta feedback", systemImage: "bubble.left.and.bubble.right")
                }
                Button {
                    model.restartOnboarding()
                    openWindow(id: "onboarding")
                } label: {
                    Label("Run setup guide again", systemImage: "list.number")
                }
                Button {
                    model.openBundledDocumentation()
                } label: {
                    Label("Open privacy and support docs", systemImage: "book.closed")
                }
            } header: {
                Text("Beta and diagnostics")
            } footer: {
                Text("Diagnostics remain on this Mac for up to 30 days and contain only outcomes, timings, app identifiers, and error codes—never writing text.")
            }

            Section {
                Picker("Activity retention", selection: Binding(
                    get: { model.historyRetentionDays },
                    set: { model.setHistoryRetentionDays($0) }
                )) {
                    ForEach(AppModel.retentionOptions, id: \.self) { days in
                        Text(days == 0 ? "Do not retain" : "\(days) days").tag(days)
                    }
                }
                Button {
                    model.exportWritingData()
                } label: {
                    Label("Export writing data", systemImage: "square.and.arrow.up")
                }
                Button("Delete today's activity") {
                    model.deleteTodayData()
                }
                Menu {
                    ForEach(model.applicationsWithStoredData) { application in
                        Button(application.name, role: .destructive) {
                            model.deleteData(for: application)
                        }
                    }
                } label: {
                    Label("Delete data for an application", systemImage: "app.badge.minus")
                }
                .disabled(model.applicationsWithStoredData.isEmpty)
                Button("Delete all data and preferences", role: .destructive) {
                    confirmDeleteAll = true
                }
            } header: {
                Text("Data controls")
            } footer: {
                Text("Profiles and activity are encrypted locally. An exported JSON file is plaintext so you can inspect and move it.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 600)
        .padding(.top, 8)
        .onAppear {
            model.refreshPermission()
            model.refreshOnDeviceModelStatus()
        }
        .alert("Delete all WriteSense data?", isPresented: $confirmDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                model.deleteAllData()
            }
        } message: {
            Text("This removes learned patterns, examples, vocabulary, activity, diagnostics, application approvals, preferences, run markers, backups, and the local encryption key. This cannot be undone.")
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var vocabularyWord = ""

    private let metricColumns = [
        GridItem(.adaptive(minimum: 125), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Writing insights")
                        .font(.largeTitle.weight(.bold))
                    Text("A private view of the habits WriteSense has learned from your edits.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    InsightMetric(title: "Reliable patterns", value: "\(model.reliablePatternCount)", icon: "brain.head.profile")
                    InsightMetric(title: "Accepted", value: "\(model.profile.acceptedSuggestionCount)", icon: "checkmark.circle")
                    InsightMetric(title: "Rejected", value: "\(model.profile.rejectedSuggestionCount)", icon: "xmark.circle")
                    InsightMetric(title: "Corrections · 7d", value: "\(model.currentWeekCorrectionCount)", icon: "pencil.and.list.clipboard")
                    InsightMetric(
                        title: "Acceptance · 7d",
                        value: "\(Int(model.currentWeekAcceptanceRate * 100))%",
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("Improvement trend", systemImage: "chart.xyaxis.line")
                        .font(.title3.weight(.semibold))
                    Text(model.improvementTrendDescription)
                        .foregroundStyle(.secondary)
                    Text("Trends use retained activity metadata and never diagnostic logs or cloud analytics.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))

                if model.learnedPatterns.isEmpty {
                    ContentUnavailableView(
                        "Your profile is still learning",
                        systemImage: "wand.and.stars",
                        description: Text("Make a few edits in an approved app. Repeated changes will appear here as patterns.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Learned patterns")
                            .font(.title3.weight(.semibold))
                        ForEach(model.learnedPatterns) { pattern in
                            PatternRow(pattern: pattern)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Personal vocabulary")
                        .font(.title3.weight(.semibold))
                    HStack {
                        TextField("Name or technical term", text: $vocabularyWord)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addVocabularyWord() }
                        Button("Add") { addVocabularyWord() }
                            .buttonStyle(.borderedProminent)
                            .disabled(vocabularyWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if model.visibleVocabulary.isEmpty {
                        Text("Accepted terminology will not be flagged as a spelling issue.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.visibleVocabulary, id: \.self) { word in
                            HStack {
                                Text(word)
                                Spacer()
                                Button {
                                    model.removeVocabularyWord(word)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Remove from vocabulary")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent correction events")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text(model.historyRetentionDays == 0 ? "Not retained" : "\(model.historyRetentionDays)-day retention")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.recentCorrectionEvents.isEmpty {
                        Text("No retained correction events. Only changed fragments—not full paragraphs—are stored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.recentCorrectionEvents) { event in
                            CorrectionEventRow(event: event)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addVocabularyWord() {
        model.addVocabularyWord(vocabularyWord)
        vocabularyWord = ""
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

struct CorrectionEventRow: View {
    @EnvironmentObject private var model: AppModel
    let event: CorrectionEvent

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .foregroundStyle(.blue)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.category.title)
                        .font(.subheadline.weight(.semibold))
                    Text(event.applicationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(event.changedFragmentBefore.isEmpty ? "∅" : event.changedFragmentBefore)  →  \(event.changedFragmentAfter.isEmpty ? "∅" : event.changedFragmentAfter)")
                    .font(.caption.monospaced())
                    .lineLimit(2)
                Text(event.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                model.deleteCorrectionEvent(event)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete this correction event")
        }
        .padding(11)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
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
                Text(model.visibleDescription(for: pattern))
                    .font(.subheadline)
                ForEach(Array(model.visibleExamples(for: pattern).prefix(3))) { example in
                    Text("\(example.before.isEmpty ? "∅" : example.before)  →  \(example.after.isEmpty ? "∅" : example.after)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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
