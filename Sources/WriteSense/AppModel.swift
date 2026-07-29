import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var isLearningActive: Bool
    @Published private(set) var capitalizationChecksEnabled: Bool
    @Published private(set) var historyRetentionDays: Int
    @Published private(set) var tonePreference: TonePreference
    @Published private(set) var onboardingCompleted: Bool
    @Published private(set) var diagnosticsEnabled: Bool
    @Published private(set) var latestCompatibilityObservation: CompatibilityObservation?
    @Published private(set) var storageAvailable: Bool
    @Published private(set) var permissionTrusted: Bool
    @Published private(set) var currentApplicationName = "No supported app detected"
    @Published private(set) var currentBundleID: String?
    @Published private(set) var statusMessage = "Learning is paused"
    @Published private(set) var profile: WritingProfile
    @Published private(set) var history: WritingHistory
    @Published private(set) var latestSuggestions: [Suggestion] = []
    @Published private(set) var lastReviewLanguage = ""
    @Published private(set) var onDeviceModelStatus: OnDeviceModelStatus = .frameworkUnavailable
    @Published private(set) var isDeepReviewing = false
    @Published var notice: String?

    private let accessibility = AccessibilityService()
    private let languageEngine = LocalLanguageEngine()
    private let foundationModelService = FoundationModelWritingService()
    private let diffEngine = TextDiffEngine()
    private let learner = PatternLearner()
    private let store: ProfileStore
    private var settings: StoredSettings
    private var timer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var currentRunID: UUID?
    private var diagnosticsDirty = false
    private var lastDiagnosticsSaveAt = Date.distantPast
    private var pendingSnapshot: String?
    private var lastObservedText: String?
    private var lastChangedAt: Date?
    private var contextKey: String?
    private var currentSessionID = UUID()
    private var activeSessionRecordID: UUID?
    private var lastAuditedCaptureFailure: (CaptureFailure, String?)?
    private var lastExternalApplicationName: String?
    private var lastExternalBundleID: String?
    private var currentCapture: CapturedParagraph?
    private var undoInfo: UndoInfo?
    private var lastPromptedParagraph: String?
    private let typingPauseInterval: TimeInterval = 0.9
    private let diagnosticsFlushInterval: TimeInterval = 15
    private let maximumReviewUTF16Length = 12_000
    private lazy var floatingPanel = FloatingSuggestionPanelController(model: self)

    static let retentionOptions = [0, 7, 30, 90, 365]

    var learnedPatterns: [LearnedPattern] {
        profile.patterns
            .filter { !visibleExamples(for: $0).isEmpty }
            .sorted { lhs, rhs in
                if lhs.isReliable != rhs.isReliable { return lhs.isReliable }
                return lhs.lastObservedAt > rhs.lastObservedAt
            }
    }

    var reliablePatternCount: Int {
        profile.patterns.filter(\.isReliable).count
    }

    var approvedApplications: [SupportedApplication] {
        let defaults = SupportedApplication.defaults.filter { settings.approvedBundleIDs.contains($0.bundleID) }
        return defaults + customApprovedApplications
    }

    var customApprovedApplications: [SupportedApplication] {
        let defaultIDs = Set(SupportedApplication.defaults.map(\.bundleID))
        return settings.customApplicationNames.compactMap { bundleID, name in
            guard settings.approvedBundleIDs.contains(bundleID), !defaultIDs.contains(bundleID) else { return nil }
            return SupportedApplication(id: bundleID, name: name, bundleID: bundleID)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var applicationsWithStoredData: [SupportedApplication] {
        var namesByBundleID = Dictionary(
            uniqueKeysWithValues: SupportedApplication.defaults.map { ($0.bundleID, $0.name) }
        )
        for (bundleID, name) in settings.customApplicationNames {
            namesByBundleID[bundleID] = name
        }
        for event in history.correctionEvents {
            namesByBundleID[event.applicationBundleID] = event.applicationName
        }

        var bundleIDs = Set(history.correctionEvents.map(\.applicationBundleID))
        bundleIDs.formUnion(history.suggestionEvents.compactMap(\.applicationBundleID))
        bundleIDs.formUnion((history.editingSessions ?? []).map(\.applicationBundleID))
        bundleIDs.formUnion((history.diagnosticEvents ?? []).compactMap(\.applicationBundleID))
        bundleIDs.formUnion((history.compatibilityObservations ?? []).map(\.applicationBundleID))
        bundleIDs.formUnion(profile.patterns.compactMap(\.applicationBundleID))
        bundleIDs.formUnion(profile.patterns.compactMap(\.exampleApplicationBundleID))
        for pattern in profile.patterns {
            bundleIDs.formUnion((pattern.supportingExamples ?? []).compactMap(\.applicationBundleID))
        }
        for sources in (profile.vocabularySources ?? [:]).values {
            bundleIDs.formUnion(sources.filter { $0 != "manual" })
        }
        bundleIDs.formUnion((profile.suggestionPreferences ?? []).compactMap(\.applicationBundleID))

        return bundleIDs.map { bundleID in
            SupportedApplication(
                id: bundleID,
                name: namesByBundleID[bundleID] ?? bundleID,
                bundleID: bundleID
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var activeApplicationIsApproved: Bool {
        guard let currentBundleID else { return false }
        return settings.approvedBundleIDs.contains(currentBundleID)
    }

    var canUndo: Bool { undoInfo != nil }
    var canUseDeepReview: Bool { permissionTrusted && onDeviceModelStatus.isAvailable && !isDeepReviewing }

    var canApplyCurrentSuggestions: Bool {
        (currentCapture?.applicationBundleID ?? currentBundleID) != "com.apple.Terminal"
    }

    var visibleVocabulary: [String] {
        profile.vocabulary.filter { word in
            guard let sources = profile.vocabularySources?[word], !sources.isEmpty else { return true }
            return sources.contains("manual") || !sources.isDisjoint(with: settings.approvedBundleIDs)
        }.sorted()
    }

    var recentCorrectionEvents: [CorrectionEvent] {
        Array(history.correctionEvents
            .filter { settings.approvedBundleIDs.contains($0.applicationBundleID) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20))
    }

    func visibleExamples(for pattern: LearnedPattern) -> [PatternExample] {
        pattern.allExamples.filter { example in
            guard let bundleID = example.applicationBundleID else { return true }
            return settings.approvedBundleIDs.contains(bundleID)
        }
    }

    func visibleDescription(for pattern: LearnedPattern) -> String {
        if let bundleID = pattern.exampleApplicationBundleID ?? pattern.applicationBundleID,
           !settings.approvedBundleIDs.contains(bundleID) {
            return "A recurring \(pattern.category.title.lowercased()) pattern."
        }
        return pattern.description
    }

    func isBundleApproved(_ bundleID: String) -> Bool {
        settings.approvedBundleIDs.contains(bundleID)
    }

    var currentWeekCorrectionCount: Int {
        events(inDaysAgoRange: 0..<7).count
    }

    var previousWeekCorrectionCount: Int {
        events(inDaysAgoRange: 7..<14).count
    }

    var currentWeekAcceptanceRate: Double {
        let events = suggestionEvents(inDaysAgoRange: 0..<7).filter {
            $0.outcome == .accepted || $0.outcome == .edited || $0.outcome == .rejected
        }
        guard !events.isEmpty else { return 0 }
        let positive = events.filter { $0.outcome == .accepted || $0.outcome == .edited }.count
        return Double(positive) / Double(events.count)
    }

    var diagnosticsSummary: DiagnosticsSummary {
        DiagnosticsSummary.make(from: history)
    }

    var recentCompatibilityObservations: [CompatibilityObservation] {
        Array((history.compatibilityObservations ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20))
    }

    var improvementTrendDescription: String {
        guard !history.correctionEvents.isEmpty else {
            return "WriteSense needs more activity before it can show a trend."
        }
        let delta = previousWeekCorrectionCount - currentWeekCorrectionCount
        if delta > 0 {
            return "You made \(delta) fewer learned corrections than in the previous seven days."
        }
        if delta < 0 {
            return "WriteSense observed \(-delta) more corrections than in the previous seven days."
        }
        return "Your correction count is unchanged from the previous seven days."
    }

    init(store: ProfileStore = ProfileStore()) {
        self.store = store
        var loadedSettings = store.loadSettings()
        let recoveredSettings = store.recoveredFileNames.contains("settings.enc")
        if recoveredSettings {
            // A previous settings backup may predate a user's revocation or
            // pause choice. Recover preferences, but fail closed for capture.
            loadedSettings.approvedBundleIDs = []
            loadedSettings.learningEnabled = false
            loadedSettings.diagnosticsEnabled = false
            loadedSettings.onboardingCompleted = false
            _ = store.save(settings: loadedSettings)
        }
        settings = loadedSettings
        isLearningActive = loadedSettings.learningEnabled
        capitalizationChecksEnabled = loadedSettings.capitalizationChecksEnabled
        historyRetentionDays = loadedSettings.historyRetentionDays
        tonePreference = loadedSettings.tonePreference
        onboardingCompleted = loadedSettings.onboardingCompleted
        diagnosticsEnabled = loadedSettings.diagnosticsEnabled
        latestCompatibilityObservation = nil

        var loadedProfile = store.loadProfile()
        let profileCountBeforeCleanup = loadedProfile.patterns.count
        let vocabularyCountBeforeCleanup = loadedProfile.vocabulary.count
        loadedProfile.patterns.removeAll { $0.applicationBundleID == "com.apple.Terminal" }
        let staleVocabulary: Set<String> = [
            "yu", "teh", "recieve", "seperate", "definately", "adress", "wich", "becuase"
        ]
        loadedProfile.vocabulary.subtract(staleVocabulary)
        for word in staleVocabulary {
            loadedProfile.vocabularySources?.removeValue(forKey: word)
        }
        profile = loadedProfile
        if profileCountBeforeCleanup != loadedProfile.patterns.count ||
            vocabularyCountBeforeCleanup != loadedProfile.vocabulary.count {
            store.save(profile: loadedProfile)
        }

        var loadedHistory = store.loadHistory()
        let originalHistory = loadedHistory
        if var sessions = loadedHistory.editingSessions {
            for index in sessions.indices where sessions[index].endedAt == nil {
                sessions[index].endedAt = sessions[index].lastUpdatedAt
            }
            loadedHistory.editingSessions = sessions
        }
        let prunedHistory = store.pruned(
            history: loadedHistory,
            retentionDays: loadedSettings.historyRetentionDays
        )
        history = prunedHistory
        latestCompatibilityObservation = prunedHistory.compatibilityObservations?.last
        if prunedHistory != originalHistory {
            store.save(history: prunedHistory)
        }

        storageAvailable = !store.hasLoadFailure && store.lastErrorMessage == nil
        permissionTrusted = AccessibilityService.Permission.isTrusted
        onDeviceModelStatus = foundationModelService.status
        if let storageError = store.lastErrorMessage {
            isLearningActive = false
            statusMessage = "Local data unavailable — learning paused"
            notice = "Local data could not be opened: \(storageError). Delete all data to recover."
        } else if let recovery = store.lastRecoveryMessage {
            notice = recoveredSettings
                ? "\(recovery) Learning, diagnostics, and application approvals were paused for safety."
                : recovery
        }
        setupLifecycleObservers()
        if diagnosticsEnabled && storageAvailable {
            beginApplicationRunTracking()
            if store.lastRecoveryMessage != nil {
                recordDiagnostic(.storageRecovery, succeeded: true)
            }
        }
        startPolling()
    }

    func completeOnboarding() {
        onboardingCompleted = true
        settings.onboardingCompleted = true
        saveSettings()
        notice = "Setup complete. Enable learning when you are ready."
    }

    func restartOnboarding() {
        onboardingCompleted = false
        settings.onboardingCompleted = false
        saveSettings()
    }

    func refreshPermission() {
        updatePermissionState(AccessibilityService.Permission.isTrusted, announceRecovery: true)
        if !permissionTrusted {
            statusMessage = "Accessibility permission required"
        }
    }

    func requestAccessibilityPermission() {
        recordAudit(.accessibilityRequested)
        AccessibilityService.Permission.request()
        notice = "Enable WriteSense in System Settings, then return here."
        refreshPermission()
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleLearning() {
        setLearningActive(!isLearningActive)
    }

    func setLearningActive(_ active: Bool) {
        guard isLearningActive != active else { return }
        if active && !storageAvailable {
            notice = "Learning cannot start until local storage is recovered."
            return
        }
        isLearningActive = active
        settings.learningEnabled = active
        saveSettings()
        recordAudit(active ? .learningEnabled : .learningDisabled)
        resetCaptureSession()
        updateStatus()
    }

    func pauseLearning() {
        guard isLearningActive else { return }
        toggleLearning()
    }

    func setCapitalizationChecksEnabled(_ enabled: Bool) {
        guard capitalizationChecksEnabled != enabled else { return }
        capitalizationChecksEnabled = enabled
        settings.capitalizationChecksEnabled = enabled
        saveSettings()
        latestSuggestions.removeAll { !enabled && $0.category == .capitalization }
        lastPromptedParagraph = nil
        notice = enabled ? "Capitalization suggestions enabled." : "Capitalization suggestions disabled."
    }

    func setHistoryRetentionDays(_ days: Int) {
        guard Self.retentionOptions.contains(days), historyRetentionDays != days else { return }
        resetCaptureSession()
        historyRetentionDays = days
        settings.historyRetentionDays = days
        saveSettings()
        history = store.pruned(history: history, retentionDays: days)
        saveHistory()
        notice = days == 0
            ? "Activity history will not be retained. Learned patterns remain available."
            : "Activity history is retained for \(days) days."
    }

    func setTonePreference(_ preference: TonePreference) {
        guard tonePreference != preference else { return }
        tonePreference = preference
        settings.tonePreference = preference
        saveSettings()
        lastPromptedParagraph = nil
        notice = "Writing preference set to “\(preference.title).”"
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        guard diagnosticsEnabled != enabled else { return }
        if !enabled {
            finishApplicationRunTracking()
            history.diagnosticEvents = nil
            history.compatibilityObservations = nil
            history.applicationRuns = nil
            latestCompatibilityObservation = nil
            diagnosticsDirty = false
        }
        diagnosticsEnabled = enabled
        settings.diagnosticsEnabled = enabled
        saveSettings()
        saveHistory()
        if enabled && storageAvailable {
            beginApplicationRunTracking()
        }
        notice = enabled
            ? "Content-free local diagnostics enabled. Nothing is uploaded."
            : "Local diagnostics and compatibility history deleted."
    }

    func toggleApplication(_ application: SupportedApplication) {
        if settings.approvedBundleIDs.contains(application.bundleID) {
            settings.approvedBundleIDs.remove(application.bundleID)
        } else {
            settings.approvedBundleIDs.insert(application.bundleID)
            if !SupportedApplication.defaults.contains(where: { $0.bundleID == application.bundleID }) {
                settings.customApplicationNames[application.bundleID] = application.name
            }
        }
        saveSettings()
        recordAudit(
            settings.approvedBundleIDs.contains(application.bundleID)
                ? .applicationApproved
                : .applicationRevoked,
            applicationBundleID: application.bundleID
        )
        resetCaptureSession()
        updateStatus()
    }

    func isApproved(_ application: SupportedApplication) -> Bool {
        settings.approvedBundleIDs.contains(application.bundleID)
    }

    func addFrontmostApplication() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmost?.bundleIdentifier
        let isSelf = frontmostBundleID == Bundle.main.bundleIdentifier || frontmostBundleID == "io.andura.writesense"
        let bundleID = isSelf ? lastExternalBundleID : frontmostBundleID
        let applicationName = isSelf
            ? lastExternalApplicationName
            : frontmost?.localizedName
        guard let bundleID, !bundleID.isEmpty else {
            notice = "Activate the application you want to approve, then try again."
            return
        }

        settings.approvedBundleIDs.insert(bundleID)
        if !SupportedApplication.defaults.contains(where: { $0.bundleID == bundleID }) {
            settings.customApplicationNames[bundleID] = applicationName ?? bundleID
        }
        saveSettings()
        recordAudit(.applicationApproved, applicationBundleID: bundleID)
        resetCaptureSession()
        notice = "Added \(applicationName ?? bundleID)."
    }

    func removeCustomApplication(_ application: SupportedApplication) {
        settings.approvedBundleIDs.remove(application.bundleID)
        settings.customApplicationNames.removeValue(forKey: application.bundleID)
        saveSettings()
        recordAudit(.applicationRevoked, applicationBundleID: application.bundleID)
        resetCaptureSession()
        notice = "Removed \(application.name)."
    }

    func reviewCurrentParagraph() {
        refreshPermission()
        guard permissionTrusted else {
            notice = "Accessibility permission is needed to review text."
            return
        }
        guard let captured = captureApprovedParagraph() else { return }
        guard reviewLengthIsSupported(captured.paragraph, operation: .localReview, bundleID: captured.applicationBundleID) else { return }
        currentCapture = captured
        lastPromptedParagraph = captured.paragraph
        let reviewStartedAt = Date()
        let analysis = languageEngine.analyze(
            captured.paragraph,
            profile: profileForAnalysis(in: captured.applicationBundleID),
            applicationBundleID: captured.applicationBundleID,
            includeCapitalization: capitalizationChecksEnabled,
            tonePreference: tonePreference
        )
        recordDiagnostic(
            .localReview,
            succeeded: true,
            startedAt: reviewStartedAt,
            applicationBundleID: captured.applicationBundleID
        )
        lastReviewLanguage = analysis.language
        latestSuggestions = analysis.suggestions
        notice = analysis.suggestions.isEmpty ? "No suggestions found in this paragraph." : nil
    }

    func refreshOnDeviceModelStatus() {
        onDeviceModelStatus = foundationModelService.status
    }

    func openAppleIntelligenceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func openBundledDocumentation() {
        guard let resources = Bundle.main.resourceURL else {
            notice = "Bundled documentation is available in packaged beta builds."
            return
        }
        let documentation = resources.appendingPathComponent("Documentation", isDirectory: true)
        guard FileManager.default.fileExists(atPath: documentation.path) else {
            notice = "Bundled documentation is available in packaged beta builds."
            return
        }
        NSWorkspace.shared.open(documentation)
    }

    func deepReviewCurrentParagraph() {
        refreshPermission()
        refreshOnDeviceModelStatus()
        guard permissionTrusted else {
            notice = "Accessibility permission is needed to review text."
            return
        }
        guard onDeviceModelStatus.isAvailable else {
            notice = onDeviceModelStatus.title
            return
        }
        guard !isDeepReviewing else { return }
        guard let captured = captureApprovedParagraph() else { return }
        guard reviewLengthIsSupported(captured.paragraph, operation: .deepReview, bundleID: captured.applicationBundleID) else { return }

        currentCapture = captured
        lastPromptedParagraph = captured.paragraph
        isDeepReviewing = true
        notice = "Reviewing privately with Apple Intelligence…"
        let deepReviewStartedAt = Date()

        Task { [weak self] in
            guard let self else { return }
            defer { self.isDeepReviewing = false }
            let analysisProfile = self.profileForAnalysis(in: captured.applicationBundleID)
            let localReviewStartedAt = Date()
            let local = self.languageEngine.analyze(
                captured.paragraph,
                profile: analysisProfile,
                applicationBundleID: captured.applicationBundleID,
                includeCapitalization: self.capitalizationChecksEnabled,
                tonePreference: self.tonePreference
            )
            self.recordDiagnostic(
                .localReview,
                succeeded: true,
                startedAt: localReviewStartedAt,
                applicationBundleID: captured.applicationBundleID
            )
            do {
                let modelSuggestions = try await self.foundationModelService.review(
                    captured.paragraph,
                    profile: analysisProfile,
                    includeCapitalization: self.capitalizationChecksEnabled
                )
                self.lastReviewLanguage = local.language
                self.latestSuggestions = self.merging(local.suggestions, with: modelSuggestions)
                self.recordDiagnostic(
                    .deepReview,
                    succeeded: true,
                    startedAt: deepReviewStartedAt,
                    applicationBundleID: captured.applicationBundleID
                )
                self.notice = "Deep Review completed entirely on this Mac."
            } catch FoundationModelServiceError.noUsableSuggestions {
                self.recordDiagnostic(
                    .deepReview,
                    succeeded: true,
                    startedAt: deepReviewStartedAt,
                    applicationBundleID: captured.applicationBundleID
                )
                self.lastReviewLanguage = local.language
                self.latestSuggestions = local.suggestions
                self.notice = local.suggestions.isEmpty
                    ? "Apple Intelligence found no corrections."
                    : "No additional Apple Intelligence corrections were found."
            } catch {
                self.recordDiagnostic(
                    .deepReview,
                    succeeded: false,
                    startedAt: deepReviewStartedAt,
                    applicationBundleID: captured.applicationBundleID,
                    errorCode: .foundationModelError
                )
                self.notice = error.localizedDescription
                self.refreshOnDeviceModelStatus()
            }
        }
    }

    func accept(_ suggestion: Suggestion) {
        apply(suggestion, replacement: suggestion.suggestedText, outcome: .accepted)
    }

    func editAndApply(_ suggestion: Suggestion, replacement: String) {
        let trimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apply(suggestion, replacement: trimmed, outcome: .edited)
    }

    func copyReplacement(_ suggestion: Suggestion) {
        copyReplacement(suggestion.suggestedText)
    }

    func copyReplacement(_ replacement: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(replacement, forType: .string)
        notice = "Copied ‘\(replacement)’. Terminal does not expose a safely writable input field."
        floatingPanel.hide()
    }

    func reject(_ suggestion: Suggestion) {
        learner.record(
            outcome: .rejected,
            for: suggestion,
            profile: &profile,
            applicationBundleID: currentCapture?.applicationBundleID ?? currentBundleID
        )
        recordFeedback(.rejected, for: suggestion)
        saveProfile()
        latestSuggestions.removeAll { $0.id == suggestion.id }
    }

    func ignore(_ suggestion: Suggestion) {
        learner.record(
            outcome: .ignored,
            for: suggestion,
            profile: &profile,
            applicationBundleID: currentCapture?.applicationBundleID ?? currentBundleID
        )
        recordFeedback(.ignored, for: suggestion)
        saveProfile()
        latestSuggestions.removeAll { $0.id == suggestion.id }
    }

    func undoLastChange() {
        guard let undoInfo,
              let captured = accessibility.focusedParagraph(),
              captured.applicationBundleID == undoInfo.applicationBundleID else {
            notice = "The last change can no longer be undone in this field."
            return
        }
        let replacementStartedAt = Date()
        let success = accessibility.replace(
            expected: undoInfo.replacement,
            with: undoInfo.original,
            at: undoInfo.range,
            in: captured
        )
        recordDiagnostic(
            .textReplacement,
            succeeded: success,
            startedAt: replacementStartedAt,
            applicationBundleID: captured.applicationBundleID,
            errorCode: success ? nil : .undoReplacementFailed
        )
        if success {
            learner.undo(
                outcome: undoInfo.outcome,
                for: undoInfo.suggestion,
                profile: &profile,
                applicationBundleID: undoInfo.applicationBundleID
            )
            recordFeedback(.undone, for: undoInfo.suggestion)
            saveProfile()
            self.undoInfo = nil
            notice = "Change undone."
            reviewCurrentParagraph()
        } else {
            notice = "The text changed, so undo was cancelled."
        }
    }

    func deletePattern(_ pattern: LearnedPattern) {
        learner.deletePattern(pattern.id, from: &profile)
        saveProfile()
    }

    func resetPersonalization() {
        resetCaptureSession()
        profile = .empty
        history.correctionEvents = []
        history.suggestionEvents = []
        history.editingSessions = nil
        latestSuggestions = []
        saveProfile()
        saveHistory()
        recordAudit(.personalizationReset)
        notice = "Personalization was reset. Application approvals and content-free diagnostics were kept."
    }

    func deleteData(for application: SupportedApplication) {
        resetCaptureSession()
        history.correctionEvents.removeAll { $0.applicationBundleID == application.bundleID }
        history.suggestionEvents.removeAll { $0.applicationBundleID == application.bundleID }
        history.editingSessions?.removeAll { $0.applicationBundleID == application.bundleID }
        history.privacyAuditEvents?.removeAll { $0.applicationBundleID == application.bundleID }
        history.diagnosticEvents?.removeAll { $0.applicationBundleID == application.bundleID }
        history.compatibilityObservations?.removeAll { $0.applicationBundleID == application.bundleID }
        if latestCompatibilityObservation?.applicationBundleID == application.bundleID {
            latestCompatibilityObservation = nil
        }
        profile.suggestionPreferences?.removeAll { $0.applicationBundleID == application.bundleID }
        profile.patterns = profile.patterns.compactMap { original in
            var pattern = original
            pattern.supportingExamples?.removeAll { $0.applicationBundleID == application.bundleID }
            if pattern.applicationBundleID == application.bundleID {
                return nil
            }
            if pattern.exampleApplicationBundleID == application.bundleID {
                guard let replacement = pattern.supportingExamples?.first else { return nil }
                pattern.exampleBefore = replacement.before
                pattern.exampleAfter = replacement.after
                pattern.exampleApplicationBundleID = replacement.applicationBundleID
                pattern.supportingExamples?.removeAll { $0.id == replacement.id }
            }
            return pattern
        }
        if var sources = profile.vocabularySources {
            for word in Array(sources.keys) {
                sources[word]?.remove(application.bundleID)
                if sources[word]?.isEmpty == true {
                    sources.removeValue(forKey: word)
                    profile.vocabulary.remove(word)
                }
            }
            profile.vocabularySources = sources
        }
        profile.updatedAt = Date()
        saveProfile()
        saveHistory()
        recordAudit(.applicationDataDeleted)
        notice = "Stored correction data for \(application.name) was deleted."
    }

    func togglePattern(_ pattern: LearnedPattern) {
        guard let index = profile.patterns.firstIndex(where: { $0.id == pattern.id }) else { return }
        profile.patterns[index].enabled.toggle()
        saveProfile()
    }

    func addVocabularyWord(_ value: String) {
        let word = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, word.count <= 100 else { return }
        profile.vocabulary.insert(word)
        var sources = profile.vocabularySources ?? [:]
        sources[word, default: []].insert("manual")
        profile.vocabularySources = sources
        profile.updatedAt = Date()
        saveProfile()
        notice = "Added “\(word)” to your vocabulary."
    }

    func removeVocabularyWord(_ value: String) {
        let word = value.lowercased()
        profile.vocabulary.remove(word)
        profile.vocabularySources?.removeValue(forKey: word)
        profile.updatedAt = Date()
        saveProfile()
    }

    func deleteCorrectionEvent(_ event: CorrectionEvent) {
        history.correctionEvents.removeAll { $0.id == event.id }
        saveHistory()
        notice = "Correction event deleted."
    }

    func deleteTodayData() {
        resetCaptureSession()
        floatingPanel.hide()
        latestSuggestions = []
        let calendar = Calendar.current
        history.correctionEvents.removeAll { calendar.isDateInToday($0.createdAt) }
        history.suggestionEvents.removeAll { calendar.isDateInToday($0.createdAt) }
        history.editingSessions?.removeAll { calendar.isDateInToday($0.startedAt) }
        history.privacyAuditEvents?.removeAll { calendar.isDateInToday($0.createdAt) }
        saveHistory()
        recordAudit(.todayDataDeleted)
        notice = "Today's temporary and activity data was deleted. Learned patterns were kept."
    }

    func exportWritingData() {
        guard storageAvailable else {
            notice = "Writing data cannot be exported because encrypted storage is unavailable."
            return
        }
        do {
            let data = try store.exportData(profile: profile, history: history, settings: settings)
            let panel = NSSavePanel()
            panel.title = "Export WriteSense Data"
            panel.nameFieldStringValue = "WriteSense-Export.json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.message = "The export contains your learned examples and is not encrypted. Store it securely."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: [.atomic])
            recordAudit(.dataExported)
            notice = "Writing data exported to \(url.lastPathComponent)."
        } catch {
            notice = "Export failed: \(error.localizedDescription)"
        }
    }

    func runCompatibilityCheck() {
        let startedAt = Date()
        guard let application = compatibilityTargetApplication(),
              let bundleID = application.bundleIdentifier else {
            let observation = CompatibilityObservation(
                applicationName: "No application",
                applicationBundleID: "unknown",
                result: .applicationUnavailable
            )
            latestCompatibilityObservation = observation
            recordCompatibility(observation, startedAt: startedAt)
            notice = observation.result.title
            return
        }

        let result: CompatibilityResult
        if !permissionTrusted {
            result = .permissionRequired
        } else if !settings.approvedBundleIDs.contains(bundleID) {
            result = .applicationNotApproved
        } else {
            switch accessibility.focusedParagraphResult(for: application) {
            case .success(let captured):
                result = captured.isWritable ? .readWrite : .readOnly
            case .failure(.secureField):
                result = .secureFieldBlocked
            case .failure(.sensitiveContext):
                result = .privateContextBlocked
            case .failure(.noFocusedElement), .failure(.emptyText):
                result = .noFocusedField
            case .failure(.unsupportedField), .failure(.unreadableText):
                result = .unsupportedField
            case .failure(.noApplication):
                result = .applicationUnavailable
            }
        }

        let version = application.bundleURL
            .flatMap(Bundle.init(url:))?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let observation = CompatibilityObservation(
            applicationName: application.localizedName ?? bundleID,
            applicationBundleID: bundleID,
            result: result,
            applicationVersion: version
        )
        latestCompatibilityObservation = observation
        recordCompatibility(observation, startedAt: startedAt)
        notice = "\(observation.applicationName): \(result.title)."
    }

    func exportDiagnostics() {
        guard diagnosticsEnabled else {
            notice = "Enable local diagnostics before exporting a diagnostic report."
            return
        }
        flushDiagnosticsIfNeeded(force: true)
        do {
            let data = try encodedJSON(DiagnosticsExport.make(from: history))
            guard try saveExport(
                data,
                title: "Export WriteSense Diagnostics",
                filename: "WriteSense-Diagnostics.json",
                message: "This content-free report contains app identifiers, outcomes, timestamps, and latency—never writing text."
            ) else { return }
            notice = "Diagnostic report exported."
        } catch {
            notice = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    func clearDiagnostics() {
        let currentRun = currentRunID.flatMap { id in
            history.applicationRuns?.first(where: { $0.id == id })
        }
        history.diagnosticEvents = nil
        history.compatibilityObservations = nil
        history.applicationRuns = currentRun.map { [$0] }
        latestCompatibilityObservation = nil
        diagnosticsDirty = false
        saveHistory()
        notice = "Local diagnostics and compatibility history cleared."
    }

    @discardableResult
    func exportBetaFeedback(
        usefulnessRating: Int,
        recommendationQualityRating: Int,
        trustRating: Int,
        keepLearningEnabled: Bool,
        issues: Set<BetaFeedbackIssue>,
        comments: String,
        includeDiagnostics: Bool
    ) -> Bool {
        let report = BetaFeedbackReport(
            usefulnessRating: min(5, max(1, usefulnessRating)),
            recommendationQualityRating: min(5, max(1, recommendationQualityRating)),
            trustRating: min(5, max(1, trustRating)),
            keepLearningEnabled: keepLearningEnabled,
            issues: issues.sorted { $0.rawValue < $1.rawValue },
            comments: String(comments.prefix(4_000)),
            diagnostics: includeDiagnostics && diagnosticsEnabled ? diagnosticsSummary : nil
        )
        do {
            let data = try encodedJSON(report)
            guard try saveExport(
                data,
                title: "Save WriteSense Beta Feedback",
                filename: "WriteSense-Beta-Feedback.json",
                message: "Only your survey answers and optional content-free summary are included. Review the JSON before sharing it."
            ) else { return false }
            notice = "Beta feedback report saved. Thank you."
            return true
        } catch {
            notice = "Feedback export failed: \(error.localizedDescription)"
            return false
        }
    }

    func deleteAllData() {
        resetCaptureSession()
        floatingPanel.hide()
        latestSuggestions = []
        undoInfo = nil
        let deleted = store.deleteAllData()

        storageAvailable = deleted
        settings = .defaults
        profile = .empty
        history = .empty
        isLearningActive = settings.learningEnabled
        capitalizationChecksEnabled = settings.capitalizationChecksEnabled
        historyRetentionDays = settings.historyRetentionDays
        tonePreference = settings.tonePreference
        onboardingCompleted = settings.onboardingCompleted
        diagnosticsEnabled = settings.diagnosticsEnabled
        latestCompatibilityObservation = nil
        currentRunID = nil
        diagnosticsDirty = false
        updateStatus()
        notice = deleted
            ? "All WriteSense data, preferences, and encryption keys were deleted."
            : "Some local data could not be deleted. \(store.lastErrorMessage ?? "Try again.")"
    }

    private func apply(_ suggestion: Suggestion, replacement: String, outcome: SuggestionOutcome) {
        guard let captured = currentCapture ?? captureApprovedParagraph() else {
            notice = "Focus the original paragraph before applying this suggestion."
            return
        }
        guard captured.applicationBundleID != "com.apple.Terminal" else {
            copyReplacement(replacement)
            return
        }
        let replacementStartedAt = Date()
        let replacementSucceeded = accessibility.replace(suggestion, with: replacement, in: captured)
        recordDiagnostic(
            .textReplacement,
            succeeded: replacementSucceeded,
            startedAt: replacementStartedAt,
            applicationBundleID: captured.applicationBundleID,
            errorCode: replacementSucceeded ? nil : .staleOrUnsupportedRange
        )
        guard replacementSucceeded else {
            notice = "The paragraph changed, so this suggestion was not applied."
            return
        }

        learner.record(
            outcome: outcome,
            for: suggestion,
            profile: &profile,
            applicationBundleID: captured.applicationBundleID
        )
        recordFeedback(outcome, for: suggestion, applicationBundleID: captured.applicationBundleID)
        saveProfile()
        undoInfo = UndoInfo(
            applicationBundleID: captured.applicationBundleID,
            range: suggestion.range,
            original: suggestion.originalText,
            replacement: replacement,
            suggestion: suggestion,
            outcome: outcome
        )
        updateStateAfterApplying(suggestion, replacement: replacement, in: captured)
        notice = outcome == .edited ? "Your edit was applied." : "Suggestion applied."
    }

    private func recordFeedback(
        _ outcome: SuggestionOutcome,
        for suggestion: Suggestion,
        applicationBundleID: String? = nil
    ) {
        guard historyRetentionDays > 0 else { return }
        history.suggestionEvents.append(SuggestionFeedbackEvent(
            category: suggestion.category,
            outcome: outcome,
            wasPersonalized: suggestion.isPersonalized,
            patternID: suggestion.patternID,
            applicationBundleID: applicationBundleID ?? currentCapture?.applicationBundleID ?? currentBundleID
        ))
        history = store.pruned(history: history, retentionDays: historyRetentionDays)
        saveHistory()
    }

    private func updateStateAfterApplying(
        _ applied: Suggestion,
        replacement: String,
        in captured: CapturedParagraph
    ) {
        let appliedRange = applied.range.nsRange
        let delta = (replacement as NSString).length - appliedRange.length
        let oldEnd = NSMaxRange(appliedRange)

        latestSuggestions = latestSuggestions.compactMap { suggestion in
            guard suggestion.id != applied.id else { return nil }
            var updated = suggestion
            let range = suggestion.range.nsRange
            if NSIntersectionRange(range, appliedRange).length > 0 ||
                (range.location >= appliedRange.location && range.location < oldEnd) {
                return nil
            }
            if range.location >= oldEnd {
                updated.range.location = max(0, range.location + delta)
            }
            return updated
        }

        let paragraph = NSMutableString(string: captured.paragraph)
        if appliedRange.location != NSNotFound,
           NSMaxRange(appliedRange) <= paragraph.length {
            paragraph.replaceCharacters(in: appliedRange, with: replacement)
        }
        let correctedParagraph = paragraph as String

        let fullText = NSMutableString(string: captured.fullText)
        let fullRange = NSRange(
            location: captured.paragraphRange.location + appliedRange.location,
            length: appliedRange.length
        )
        if fullRange.location != NSNotFound, NSMaxRange(fullRange) <= fullText.length {
            fullText.replaceCharacters(in: fullRange, with: replacement)
        }

        currentCapture = CapturedParagraph(
            applicationName: captured.applicationName,
            applicationBundleID: captured.applicationBundleID,
            fullText: fullText as String,
            paragraph: correctedParagraph,
            paragraphRange: TextRange(
                location: captured.paragraphRange.location,
                length: max(0, captured.paragraphRange.length + delta)
            ),
            element: captured.element,
            elementFrame: captured.elementFrame,
            isWritable: captured.isWritable
        )
        lastPromptedParagraph = correctedParagraph
        lastObservedText = correctedParagraph
        pendingSnapshot = correctedParagraph
        lastChangedAt = Date()
    }

    private func reviewLengthIsSupported(
        _ paragraph: String,
        operation: DiagnosticOperation,
        bundleID: String
    ) -> Bool {
        guard (paragraph as NSString).length <= maximumReviewUTF16Length else {
            recordDiagnostic(
                operation,
                succeeded: false,
                applicationBundleID: bundleID,
                errorCode: .paragraphTooLong
            )
            notice = "This paragraph is too long for a safe interactive review. Review a shorter paragraph."
            return false
        }
        return true
    }

    private func compatibilityTargetApplication() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier,
           bundleID != "io.andura.writesense" {
            rememberExternalApplication(frontmost)
            return frontmost
        }
        guard let lastExternalBundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: lastExternalBundleID).first
    }

    private func recordCompatibility(_ observation: CompatibilityObservation, startedAt: Date) {
        guard diagnosticsEnabled, storageAvailable else { return }
        var observations = history.compatibilityObservations ?? []
        observations.append(observation)
        history.compatibilityObservations = observations
        recordDiagnostic(
            .compatibilityCheck,
            succeeded: observation.result.isSuccessfulSafetyResult,
            startedAt: startedAt,
            applicationBundleID: observation.applicationBundleID,
            errorCode: observation.result.isSuccessfulSafetyResult ? nil : observation.result.diagnosticErrorCode
        )
        if observation.result == .secureFieldBlocked || observation.result == .privateContextBlocked {
            recordDiagnostic(
                .secureContextBlocked,
                succeeded: true,
                applicationBundleID: observation.applicationBundleID,
                errorCode: observation.result.diagnosticErrorCode
            )
        }
        history = store.pruned(history: history, retentionDays: historyRetentionDays)
        saveHistory()
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func saveExport(
        _ data: Data,
        title: String,
        filename: String,
        message: String
    ) throws -> Bool {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: [.atomic])
        return true
    }

    private func setupLifecycleObservers() {
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            MainActor.assumeIsolated {
                self?.rememberExternalApplication(application)
            }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareForTermination()
            }
        }
    }

    private func rememberExternalApplication(_ application: NSRunningApplication) {
        guard let bundleID = application.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              bundleID != "io.andura.writesense" else { return }
        lastExternalBundleID = bundleID
        lastExternalApplicationName = application.localizedName ?? bundleID
    }

    private func beginApplicationRunTracking() {
        guard currentRunID == nil,
              let start = store.beginApplicationRun() else { return }
        var runs = history.applicationRuns ?? []
        var foundUncleanRun = false
        for index in runs.indices where runs[index].cleanExit == nil {
            runs[index].endedAt = Date()
            runs[index].cleanExit = false
            foundUncleanRun = true
        }
        if let previous = start.previousUnclean {
            if let index = runs.firstIndex(where: { $0.id == previous.id }) {
                runs[index].endedAt = Date()
                runs[index].cleanExit = false
            } else {
                runs.append(ApplicationRunRecord(
                    id: previous.id,
                    startedAt: previous.startedAt,
                    endedAt: Date(),
                    cleanExit: false
                ))
            }
            foundUncleanRun = true
        }
        if foundUncleanRun {
            var diagnostics = history.diagnosticEvents ?? []
            diagnostics.append(DiagnosticEvent(
                operation: .uncleanTermination,
                succeeded: false,
                errorCode: .previousRunDidNotExitCleanly
            ))
            history.diagnosticEvents = diagnostics
        }
        runs.append(ApplicationRunRecord(
            id: start.current.id,
            startedAt: start.current.startedAt
        ))
        history.applicationRuns = runs
        currentRunID = start.current.id
        history = store.pruned(history: history, retentionDays: historyRetentionDays)
        saveHistory()
    }

    private func finishApplicationRunTracking() {
        guard let currentRunID else { return }
        finalizeEditingSession()
        if let index = history.applicationRuns?.firstIndex(where: { $0.id == currentRunID }) {
            history.applicationRuns?[index].endedAt = Date()
            history.applicationRuns?[index].cleanExit = true
        }
        if storageAvailable && store.save(history: history) {
            store.finishApplicationRun(currentRunID)
            diagnosticsDirty = false
            lastDiagnosticsSaveAt = Date()
        }
        self.currentRunID = nil
    }

    private func prepareForTermination() {
        timer?.invalidate()
        flushDiagnosticsIfNeeded(force: true)
        finishApplicationRunTracking()
    }

    private func recordDiagnostic(
        _ operation: DiagnosticOperation,
        succeeded: Bool,
        startedAt: Date? = nil,
        applicationBundleID: String? = nil,
        errorCode: DiagnosticErrorCode? = nil
    ) {
        guard diagnosticsEnabled, storageAvailable else { return }
        let duration = startedAt.map { max(0, Date().timeIntervalSince($0) * 1_000) }
        var events = history.diagnosticEvents ?? []
        events.append(DiagnosticEvent(
            operation: operation,
            succeeded: succeeded,
            durationMilliseconds: duration,
            applicationBundleID: applicationBundleID,
            errorCode: errorCode
        ))
        history.diagnosticEvents = events
        diagnosticsDirty = true
    }

    private func flushDiagnosticsIfNeeded(force: Bool = false) {
        guard diagnosticsDirty,
              force || Date().timeIntervalSince(lastDiagnosticsSaveAt) >= diagnosticsFlushInterval else { return }
        history = store.pruned(history: history, retentionDays: historyRetentionDays)
        saveHistory()
    }

    private func startPolling() {
        let pollingTimer = Timer(timeInterval: 1.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollFocusedText()
            }
        }
        pollingTimer.tolerance = 0.25
        // Common mode keeps permission/status updates alive while the menu bar
        // popover is open and macOS is tracking menu events.
        RunLoop.main.add(pollingTimer, forMode: .common)
        timer = pollingTimer
    }

    private func pollFocusedText() {
        flushDiagnosticsIfNeeded()
        updatePermissionState(AccessibilityService.Permission.isTrusted, announceRecovery: true)
        guard permissionTrusted else {
            statusMessage = "Accessibility permission required"
            resetCaptureSession()
            return
        }
        guard storageAvailable else {
            statusMessage = "Local data unavailable — learning paused"
            resetCaptureSession()
            return
        }
        guard isLearningActive else {
            statusMessage = "Learning is paused"
            return
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        currentApplicationName = frontmost?.localizedName ?? "No application"
        currentBundleID = frontmost?.bundleIdentifier
        guard let bundleID = currentBundleID else {
            statusMessage = "No supported app detected"
            resetCaptureSession()
            return
        }
        if bundleID != Bundle.main.bundleIdentifier && bundleID != "io.andura.writesense" {
            lastExternalBundleID = bundleID
            lastExternalApplicationName = frontmost?.localizedName ?? bundleID
        }
        guard settings.approvedBundleIDs.contains(bundleID) else {
            statusMessage = "Blocked in this application"
            resetCaptureSession()
            return
        }

        let captureResult = accessibility.focusedParagraphResult(for: frontmost)
        guard case .success(let captured) = captureResult else {
            if case .failure(let reason) = captureResult {
                statusMessage = reason.statusMessage
                if (reason == .secureField || reason == .sensitiveContext),
                   lastAuditedCaptureFailure?.0 != reason || lastAuditedCaptureFailure?.1 != bundleID {
                    recordAudit(
                        reason == .secureField ? .secureFieldBlocked : .privateContextBlocked,
                        applicationBundleID: bundleID
                    )
                    recordDiagnostic(
                        .secureContextBlocked,
                        succeeded: true,
                        applicationBundleID: bundleID,
                        errorCode: reason == .secureField ? .secureFieldBlocked : .privateContextBlocked
                    )
                    lastAuditedCaptureFailure = (reason, bundleID)
                }
            }
            resetCaptureSession()
            return
        }

        lastAuditedCaptureFailure = nil
        currentCapture = captured
        statusMessage = "Learning in \(captured.applicationName)"
        let key = "\(captured.applicationBundleID):\(captured.paragraphRange.location)"
        if key != contextKey {
            finalizeEditingSession()
            contextKey = key
            currentSessionID = UUID()
            beginEditingSession(for: captured)
            pendingSnapshot = captured.paragraph
            lastObservedText = captured.paragraph
            lastChangedAt = Date()
            return
        }

        if lastObservedText != captured.paragraph {
            lastObservedText = captured.paragraph
            lastChangedAt = Date()
            return
        }

        guard let lastChangedAt,
              Date().timeIntervalSince(lastChangedAt) >= typingPauseInterval else { return }

        if let snapshot = pendingSnapshot, snapshot != captured.paragraph {
            let diffStartedAt = Date()
            let diffs = diffEngine.diffs(before: snapshot, after: captured.paragraph)
            recordDiagnostic(
                .diffGeneration,
                succeeded: true,
                startedAt: diffStartedAt,
                applicationBundleID: captured.applicationBundleID
            )
            if captured.applicationBundleID != "com.apple.Terminal" {
                var learnedEvents: [CorrectionEvent] = []
                for diff in diffs where diff.isMeaningful {
                    if let event = learner.learn(
                        from: diff,
                        in: snapshot,
                        fullAfter: captured.paragraph,
                        profile: &profile,
                        applicationBundleID: captured.applicationBundleID,
                        applicationName: captured.applicationName,
                        sessionID: currentSessionID
                    ) {
                        learnedEvents.append(event)
                    }
                }
                if !learnedEvents.isEmpty {
                    saveProfile()
                    if historyRetentionDays > 0 {
                        history.correctionEvents.append(contentsOf: learnedEvents)
                        if let activeSessionRecordID,
                           let index = history.editingSessions?.firstIndex(where: { $0.id == activeSessionRecordID }) {
                            history.editingSessions?[index].correctionCount += learnedEvents.count
                            history.editingSessions?[index].lastUpdatedAt = Date()
                        }
                        history = store.pruned(history: history, retentionDays: historyRetentionDays)
                        saveHistory()
                    }
                }
            }
        }

        // Offer help automatically once per stable paragraph. This also runs
        // when the paragraph was already complete when WriteSense started.
        if lastPromptedParagraph != captured.paragraph {
            lastPromptedParagraph = captured.paragraph
            if (captured.paragraph as NSString).length <= maximumReviewUTF16Length {
                let reviewStartedAt = Date()
                let analysis = languageEngine.analyze(
                    captured.paragraph,
                    profile: profileForAnalysis(in: captured.applicationBundleID),
                    applicationBundleID: captured.applicationBundleID,
                    includeCapitalization: capitalizationChecksEnabled,
                    tonePreference: tonePreference
                )
                recordDiagnostic(
                    .localReview,
                    succeeded: true,
                    startedAt: reviewStartedAt,
                    applicationBundleID: captured.applicationBundleID
                )
                if !analysis.suggestions.isEmpty {
                    lastReviewLanguage = analysis.language
                    latestSuggestions = analysis.suggestions
                    floatingPanel.show(near: captured.elementFrame)
                }
            } else {
                recordDiagnostic(
                    .localReview,
                    succeeded: false,
                    applicationBundleID: captured.applicationBundleID,
                    errorCode: .paragraphTooLong
                )
            }
        }

        pendingSnapshot = captured.paragraph
        self.lastChangedAt = Date()
    }

    private func captureApprovedParagraph() -> CapturedParagraph? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleID = application.bundleIdentifier else {
            notice = "Focus a text field in an approved application first."
            return nil
        }
        guard settings.approvedBundleIDs.contains(bundleID) else {
            notice = "\(application.localizedName ?? bundleID) is not approved in WriteSense settings."
            return nil
        }
        switch accessibility.focusedParagraphResult(for: application) {
        case .success(let captured):
            return captured
        case .failure(let reason):
            notice = reason.statusMessage
            return nil
        }
    }

    private func beginEditingSession(for captured: CapturedParagraph) {
        guard historyRetentionDays > 0 else {
            activeSessionRecordID = nil
            return
        }
        let record = EditingSessionRecord(
            id: currentSessionID,
            applicationName: captured.applicationName,
            applicationBundleID: captured.applicationBundleID
        )
        var sessions = history.editingSessions ?? []
        sessions.append(record)
        history.editingSessions = sessions
        activeSessionRecordID = record.id
        history = store.pruned(history: history, retentionDays: historyRetentionDays)
        saveHistory()
    }

    private func finalizeEditingSession() {
        guard let activeSessionRecordID,
              let index = history.editingSessions?.firstIndex(where: { $0.id == activeSessionRecordID }) else {
            self.activeSessionRecordID = nil
            return
        }
        let now = Date()
        history.editingSessions?[index].lastUpdatedAt = now
        history.editingSessions?[index].endedAt = now
        self.activeSessionRecordID = nil
        saveHistory()
    }

    private func recordAudit(
        _ action: PrivacyAuditAction,
        applicationBundleID: String? = nil
    ) {
        guard historyRetentionDays > 0 else { return }
        var events = history.privacyAuditEvents ?? []
        events.append(PrivacyAuditEvent(
            action: action,
            applicationBundleID: applicationBundleID
        ))
        history.privacyAuditEvents = events
        history = store.pruned(history: history, retentionDays: historyRetentionDays)
        saveHistory()
    }

    private func resetCaptureSession() {
        finalizeEditingSession()
        pendingSnapshot = nil
        lastObservedText = nil
        lastChangedAt = nil
        contextKey = nil
        currentSessionID = UUID()
        currentCapture = nil
        lastPromptedParagraph = nil
        floatingPanel.hide()
    }

    private func updatePermissionState(_ trusted: Bool, announceRecovery: Bool) {
        guard permissionTrusted != trusted else { return }
        permissionTrusted = trusted
        if trusted {
            recordDiagnostic(.permissionRestored, succeeded: true)
            statusMessage = isLearningActive ? "Ready to learn" : "Learning is paused"
            if announceRecovery {
                notice = "Accessibility permission restored."
            }
        } else {
            recordDiagnostic(
                .permissionUnavailable,
                succeeded: false,
                errorCode: .accessibilityPermissionMissing
            )
            statusMessage = "Accessibility permission required"
            resetCaptureSession()
            if announceRecovery {
                notice = "Accessibility permission was removed. Learning has stopped."
            }
        }
    }

    private func updateStatus() {
        if !permissionTrusted {
            statusMessage = "Accessibility permission required"
        } else if !isLearningActive {
            statusMessage = "Learning is paused"
        } else {
            statusMessage = "Ready to learn"
        }
    }

    private func merging(_ local: [Suggestion], with model: [Suggestion]) -> [Suggestion] {
        var merged = local
        for candidate in model {
            let overlaps = merged.contains { existing in
                let intersection = NSIntersectionRange(existing.range.nsRange, candidate.range.nsRange)
                return intersection.length > 0 ||
                    (existing.range.location == candidate.range.location &&
                     existing.range.length == 0 && candidate.range.length == 0) ||
                    (existing.originalText == candidate.originalText &&
                     existing.suggestedText == candidate.suggestedText)
            }
            if !overlaps { merged.append(candidate) }
        }
        return merged.sorted {
            if $0.isPersonalized != $1.isPersonalized { return $0.isPersonalized }
            return $0.confidence > $1.confidence
        }
    }

    private func profileForAnalysis(in applicationBundleID: String) -> WritingProfile {
        var filtered = profile
        filtered.vocabulary = Set(visibleVocabulary)
        filtered.vocabularySources = filtered.vocabularySources?.filter { filtered.vocabulary.contains($0.key) }
        filtered.suggestionPreferences = profile.suggestionPreferences?.filter { preference in
            preference.applicationBundleID == nil || preference.applicationBundleID == applicationBundleID
        }
        filtered.patterns = profile.patterns.compactMap { original in
            if let scopedApp = original.applicationBundleID, scopedApp != applicationBundleID {
                return nil
            }
            var pattern = original
            pattern.supportingExamples = pattern.supportingExamples?.filter { example in
                guard let bundleID = example.applicationBundleID else { return true }
                return settings.approvedBundleIDs.contains(bundleID)
            }
            if let primaryApp = pattern.exampleApplicationBundleID,
               !settings.approvedBundleIDs.contains(primaryApp) {
                guard let replacement = pattern.supportingExamples?.first else { return nil }
                pattern.exampleBefore = replacement.before
                pattern.exampleAfter = replacement.after
                pattern.exampleApplicationBundleID = replacement.applicationBundleID
                pattern.supportingExamples?.removeAll { $0.id == replacement.id }
            }
            return pattern
        }
        return filtered
    }

    private func events(inDaysAgoRange range: Range<Int>) -> [CorrectionEvent] {
        let calendar = Calendar.current
        let now = Date()
        guard let newer = calendar.date(byAdding: .day, value: -range.lowerBound, to: now),
              let older = calendar.date(byAdding: .day, value: -range.upperBound, to: now) else { return [] }
        return history.correctionEvents.filter { $0.createdAt <= newer && $0.createdAt > older }
    }

    private func suggestionEvents(inDaysAgoRange range: Range<Int>) -> [SuggestionFeedbackEvent] {
        let calendar = Calendar.current
        let now = Date()
        guard let newer = calendar.date(byAdding: .day, value: -range.lowerBound, to: now),
              let older = calendar.date(byAdding: .day, value: -range.upperBound, to: now) else { return [] }
        return history.suggestionEvents.filter { $0.createdAt <= newer && $0.createdAt > older }
    }

    private func saveProfile() {
        if !store.save(profile: profile) {
            markStorageUnavailable("Writing profile could not be saved")
        }
    }

    private func saveHistory() {
        if !store.save(history: history) {
            markStorageUnavailable("Writing history could not be saved")
        } else {
            diagnosticsDirty = false
            lastDiagnosticsSaveAt = Date()
        }
    }

    private func saveSettings() {
        if !store.save(settings: settings) {
            markStorageUnavailable("Settings could not be saved")
        }
    }

    private func markStorageUnavailable(_ message: String) {
        storageAvailable = false
        isLearningActive = false
        statusMessage = "Local data unavailable — learning paused"
        pendingSnapshot = nil
        lastObservedText = nil
        lastChangedAt = nil
        contextKey = nil
        activeSessionRecordID = nil
        currentCapture = nil
        lastPromptedParagraph = nil
        floatingPanel.hide()
        notice = "\(message): \(store.lastErrorMessage ?? "Unknown error"). Delete all data to recover."
    }
}

private struct UndoInfo {
    let applicationBundleID: String
    let range: TextRange
    let original: String
    let replacement: String
    let suggestion: Suggestion
    let outcome: SuggestionOutcome
}
