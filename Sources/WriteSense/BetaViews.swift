import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private let stepCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to WriteSense")
                        .font(.largeTitle.weight(.bold))
                    Text("Private, personalized writing guidance across approved Mac apps.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(step + 1) of \(stepCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(step + 1), total: Double(stepCount))

            Group {
                switch step {
                case 0: privacyStep
                case 1: permissionStep
                case 2: applicationsStep
                case 3: preferencesStep
                default: exampleStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                Button("Back") { step = max(0, step - 1) }
                    .disabled(step == 0)
                Spacer()
                if step < stepCount - 1 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Finish setup") {
                        model.completeOnboarding()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 580, minHeight: 480)
        .onAppear {
            model.refreshPermission()
        }
    }

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("You control every capture boundary", systemImage: "hand.raised.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.blue)
            OnboardingPoint(
                icon: "text.quote",
                title: "What WriteSense reads",
                detail: "The current paragraph in an application you explicitly approve, after a typing pause or manual review."
            )
            OnboardingPoint(
                icon: "nosign",
                title: "What it never captures",
                detail: "Raw keystrokes, screenshots, clipboard contents, passwords, secure fields, or detectable private-browser windows."
            )
            OnboardingPoint(
                icon: "lock.shield",
                title: "Where learning stays",
                detail: "Profiles and retained activity are AES-GCM encrypted. The key remains in this Mac’s Keychain."
            )
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Accessibility permission", systemImage: "checkmark.shield")
                .font(.title2.weight(.semibold))
            Text("macOS requires Accessibility permission so WriteSense can read and safely replace text in approved fields. Permission does not bypass the app allowlist or secure-field blocking.")
                .foregroundStyle(.secondary)
            HStack {
                Label(
                    model.permissionTrusted ? "Permission granted" : "Permission required",
                    systemImage: model.permissionTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .foregroundStyle(model.permissionTrusted ? .green : .orange)
                Spacer()
                Button(model.permissionTrusted ? "Open System Settings" : "Grant permission") {
                    model.requestAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            Button("Refresh permission status") {
                model.refreshPermission()
            }
        }
    }

    private var applicationsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Choose approved applications", systemImage: "app.badge.checkmark")
                .font(.title2.weight(.semibold))
            Text("Everything else stays blocked. Terminal is off by default and remains Copy-only if enabled.")
                .foregroundStyle(.secondary)
            ForEach(SupportedApplication.defaults) { application in
                Toggle(isOn: Binding(
                    get: { model.isApproved(application) },
                    set: { _ in model.toggleApplication(application) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(application.name)
                        if application.isSuggestionOnly {
                            Text("Suggestion and Copy only")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Local data preferences", systemImage: "externaldrive.badge.checkmark")
                .font(.title2.weight(.semibold))
            Picker("Writing preference", selection: Binding(
                get: { model.tonePreference },
                set: { model.setTonePreference($0) }
            )) {
                ForEach(TonePreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            Picker("Activity retention", selection: Binding(
                get: { model.historyRetentionDays },
                set: { model.setHistoryRetentionDays($0) }
            )) {
                ForEach(AppModel.retentionOptions, id: \.self) { days in
                    Text(days == 0 ? "Do not retain writing activity" : "\(days) days").tag(days)
                }
            }
            Toggle("Keep content-free beta diagnostics locally", isOn: Binding(
                get: { model.diagnosticsEnabled },
                set: { model.setDiagnosticsEnabled($0) }
            ))
            Text("Diagnostics contain app identifiers, outcomes, timestamps, latency, and static error codes. They never contain paragraphs, changed fragments, vocabulary, or document names, and nothing is uploaded automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var exampleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("How personalized learning works", systemImage: "sparkles")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                Text("You manually edit:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("I send it yesterday")
                        .strikethrough()
                        .foregroundStyle(.red)
                    Image(systemName: "arrow.right")
                    Text("I sent it yesterday")
                        .fontWeight(.semibold)
                }
                Text("After repeated related edits, WriteSense can prioritize another past-tense correction and explain that it matches your history.")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Label("Nothing changes automatically. Apply, edit, reject, ignore, and undo remain under your control.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
            Toggle("Start learning after setup", isOn: Binding(
                get: { model.isLearningActive },
                set: { model.setLearningActive($0) }
            ))
            .disabled(!model.permissionTrusted || !model.storageAvailable)
        }
    }
}

private struct OnboardingPoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmClear = false

    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 10)]

    var body: some View {
        let summary = model.diagnosticsSummary
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Beta diagnostics")
                        .font(.largeTitle.weight(.bold))
                    Text("Content-free reliability and compatibility data stored only on this Mac.")
                        .foregroundStyle(.secondary)
                }

                if !model.diagnosticsEnabled {
                    ContentUnavailableView(
                        "Local diagnostics are disabled",
                        systemImage: "stethoscope",
                        description: Text("Enable them in Settings to collect beta reliability metrics.")
                    )
                    .frame(minHeight: 220)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        DiagnosticMetricCard(
                            title: "Crash-free runs",
                            value: percent(summary.crashFreeRunRate),
                            icon: "checkmark.shield"
                        )
                        DiagnosticMetricCard(
                            title: "Average local review",
                            value: milliseconds(summary.averageLocalReviewMilliseconds),
                            icon: "timer"
                        )
                        DiagnosticMetricCard(
                            title: "P95 local review",
                            value: milliseconds(summary.p95LocalReviewMilliseconds),
                            icon: "gauge.with.dots.needle.67percent"
                        )
                        DiagnosticMetricCard(
                            title: "Replacement failures",
                            value: "\(summary.replacementFailureCount)",
                            icon: "exclamationmark.arrow.triangle.2.circlepath"
                        )
                        DiagnosticMetricCard(
                            title: "Permission failures",
                            value: "\(summary.permissionFailureCount)",
                            icon: "lock.trianglebadge.exclamationmark"
                        )
                        DiagnosticMetricCard(
                            title: "Active days · 7d",
                            value: "\(summary.weeklyActiveDays)",
                            icon: "calendar"
                        )
                    }

                    HStack {
                        Button {
                            model.runCompatibilityCheck()
                        } label: {
                            Label("Check last active app", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            model.exportDiagnostics()
                        } label: {
                            Label("Export report", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("Clear diagnostics", role: .destructive) {
                            confirmClear = true
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent compatibility checks")
                            .font(.title3.weight(.semibold))
                        if model.recentCompatibilityObservations.isEmpty {
                            Text("Focus a text field in an approved app, return to WriteSense, and run a check. No field text is retained.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.recentCompatibilityObservations) { observation in
                                HStack(spacing: 10) {
                                    Image(systemName: observation.result.isSuccessfulSafetyResult ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundStyle(observation.result.isSuccessfulSafetyResult ? .green : .orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(observation.applicationName)
                                            .font(.subheadline.weight(.semibold))
                                        Text(observation.result.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(observation.createdAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }

                    Text("An unclean run means the previous process did not remove its content-free launch marker. It can indicate a crash, forced quit, power loss, or test termination—not necessarily an application defect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .alert("Clear local diagnostics?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { model.clearDiagnostics() }
        } message: {
            Text("This removes compatibility checks, timing events, and completed run history. Writing profile data is not affected.")
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value < 1_000
            ? "\(Int(value.rounded())) ms"
            : String(format: "%.1f s", value / 1_000)
    }
}

private struct DiagnosticMetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.blue)
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct BetaFeedbackView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var usefulness = 3
    @State private var recommendationQuality = 3
    @State private var trust = 3
    @State private var keepLearningEnabled = true
    @State private var issues: Set<BetaFeedbackIssue> = []
    @State private var comments = ""
    @State private var includeDiagnostics = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Beta feedback")
                        .font(.largeTitle.weight(.bold))
                    Text("Create a reviewable JSON report to share with the WriteSense team.")
                        .foregroundStyle(.secondary)
                }

                RatingPicker(title: "Overall usefulness", value: $usefulness)
                RatingPicker(title: "Recommendation quality", value: $recommendationQuality)
                RatingPicker(title: "Trust and privacy clarity", value: $trust)

                Toggle("I would keep learning enabled", isOn: $keepLearningEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What needs improvement?")
                        .font(.headline)
                    ForEach(BetaFeedbackIssue.allCases) { issue in
                        Toggle(issue.title, isOn: Binding(
                            get: { issues.contains(issue) },
                            set: { selected in
                                if selected { issues.insert(issue) }
                                else { issues.remove(issue) }
                            }
                        ))
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Comments")
                        .font(.headline)
                    TextEditor(text: $comments)
                        .font(.body)
                        .frame(minHeight: 100)
                        .padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)
                        }
                    Label("Do not paste private writing, passwords, access tokens, or client information.", systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("Include content-free diagnostic summary", isOn: $includeDiagnostics)
                    .disabled(!model.diagnosticsEnabled)
                Text("No report is uploaded automatically. WriteSense opens a save panel, and you can inspect the JSON before sharing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Save feedback report") {
                        if model.exportBetaFeedback(
                            usefulnessRating: usefulness,
                            recommendationQualityRating: recommendationQuality,
                            trustRating: trust,
                            keepLearningEnabled: keepLearningEnabled,
                            issues: issues,
                            comments: comments,
                            includeDiagnostics: includeDiagnostics
                        ) {
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .onAppear {
            keepLearningEnabled = model.isLearningActive
            includeDiagnostics = model.diagnosticsEnabled
        }
    }
}

private struct RatingPicker: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Picker(title, selection: $value) {
                ForEach(1...5, id: \.self) { rating in
                    Text("\(rating)").tag(rating)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }
}
