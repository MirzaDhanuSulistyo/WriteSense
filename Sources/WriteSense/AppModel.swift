import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var isLearningActive: Bool
    @Published private(set) var permissionTrusted: Bool
    @Published private(set) var currentApplicationName = "No supported app detected"
    @Published private(set) var currentBundleID: String?
    @Published private(set) var statusMessage = "Learning is paused"
    @Published private(set) var profile: WritingProfile
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
    private let store = ProfileStore()
    private var settings: StoredSettings
    private var timer: Timer?
    private var pendingSnapshot: String?
    private var lastObservedText: String?
    private var lastChangedAt: Date?
    private var contextKey: String?
    private var currentCapture: CapturedParagraph?
    private var undoInfo: UndoInfo?
    private var lastPromptedParagraph: String?
    private let typingPauseInterval: TimeInterval = 0.9
    private lazy var floatingPanel = FloatingSuggestionPanelController(model: self)

    var learnedPatterns: [LearnedPattern] {
        profile.patterns.sorted { lhs, rhs in
            if lhs.isReliable != rhs.isReliable { return lhs.isReliable }
            return lhs.lastObservedAt > rhs.lastObservedAt
        }
    }

    var reliablePatternCount: Int {
        profile.patterns.filter(\.isReliable).count
    }

    var approvedApplications: [SupportedApplication] {
        SupportedApplication.defaults.filter { settings.approvedBundleIDs.contains($0.bundleID) }
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

    init() {
        let loadedSettings = store.loadSettings()
        settings = loadedSettings
        isLearningActive = loadedSettings.learningEnabled
        var loadedProfile = store.loadProfile()
        loadedProfile.patterns.removeAll { $0.applicationBundleID == "com.apple.Terminal" }
        loadedProfile.vocabulary.subtract([
            "yu", "teh", "recieve", "seperate", "definately", "adress", "wich", "becuase"
        ])
        profile = loadedProfile
        store.save(profile: loadedProfile)
        permissionTrusted = AccessibilityService.Permission.isTrusted
        onDeviceModelStatus = foundationModelService.status
        startPolling()
    }

    func refreshPermission() {
        permissionTrusted = AccessibilityService.Permission.isTrusted
        if !permissionTrusted {
            statusMessage = "Accessibility permission required"
        } else if statusMessage == "Accessibility permission required" {
            statusMessage = isLearningActive ? "Ready to learn" : "Learning is paused"
        }
    }

    func requestAccessibilityPermission() {
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
        isLearningActive = active
        settings.learningEnabled = active
        store.save(settings: settings)
        resetCaptureSession()
        updateStatus()
    }

    func pauseLearning() {
        guard isLearningActive else { return }
        toggleLearning()
    }

    func toggleApplication(_ application: SupportedApplication) {
        if settings.approvedBundleIDs.contains(application.bundleID) {
            settings.approvedBundleIDs.remove(application.bundleID)
        } else {
            settings.approvedBundleIDs.insert(application.bundleID)
        }
        store.save(settings: settings)
        resetCaptureSession()
        updateStatus()
    }

    func isApproved(_ application: SupportedApplication) -> Bool {
        settings.approvedBundleIDs.contains(application.bundleID)
    }

    func addFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleID = application.bundleIdentifier,
              !bundleID.isEmpty else { return }
        settings.approvedBundleIDs.insert(bundleID)
        store.save(settings: settings)
        notice = "Added \(application.localizedName ?? bundleID)."
    }

    func reviewCurrentParagraph() {
        refreshPermission()
        guard permissionTrusted else {
            notice = "Accessibility permission is needed to review text."
            return
        }
        guard let captured = captureApprovedParagraph() else {
            notice = "Focus a text field in an approved application first."
            return
        }
        currentCapture = captured
        lastPromptedParagraph = captured.paragraph
        let analysis = languageEngine.analyze(captured.paragraph, profile: profile, applicationBundleID: captured.applicationBundleID)
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
        guard let captured = captureApprovedParagraph() else {
            notice = "Focus a text field in an approved application first."
            return
        }

        currentCapture = captured
        lastPromptedParagraph = captured.paragraph
        isDeepReviewing = true
        notice = "Reviewing privately with Apple Intelligence…"

        Task { [weak self] in
            guard let self else { return }
            defer { self.isDeepReviewing = false }
            let local = self.languageEngine.analyze(
                captured.paragraph,
                profile: self.profile,
                applicationBundleID: captured.applicationBundleID
            )
            do {
                let modelSuggestions = try await self.foundationModelService.review(
                    captured.paragraph,
                    profile: self.profile
                )
                self.lastReviewLanguage = local.language
                self.latestSuggestions = self.merging(local.suggestions, with: modelSuggestions)
                self.notice = "Deep Review completed entirely on this Mac."
            } catch FoundationModelServiceError.noUsableSuggestions {
                self.lastReviewLanguage = local.language
                self.latestSuggestions = local.suggestions
                self.notice = local.suggestions.isEmpty
                    ? "Apple Intelligence found no corrections."
                    : "No additional Apple Intelligence corrections were found."
            } catch {
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
        learner.record(outcome: .rejected, for: suggestion, profile: &profile)
        saveProfile()
        latestSuggestions.removeAll { $0.id == suggestion.id }
    }

    func ignore(_ suggestion: Suggestion) {
        latestSuggestions.removeAll { $0.id == suggestion.id }
    }

    func undoLastChange() {
        guard let undoInfo,
              let captured = accessibility.focusedParagraph(),
              captured.applicationBundleID == undoInfo.applicationBundleID else {
            notice = "The last change can no longer be undone in this field."
            return
        }
        let success = accessibility.replace(
            expected: undoInfo.replacement,
            with: undoInfo.original,
            at: undoInfo.range,
            in: captured
        )
        if success {
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

    func togglePattern(_ pattern: LearnedPattern) {
        guard let index = profile.patterns.firstIndex(where: { $0.id == pattern.id }) else { return }
        profile.patterns[index].enabled.toggle()
        saveProfile()
    }

    func deleteTodayData() {
        resetCaptureSession()
        floatingPanel.hide()
        latestSuggestions = []
        notice = "Temporary learning data was deleted."
    }

    func deleteAllData() {
        resetCaptureSession()
        floatingPanel.hide()
        profile = .empty
        latestSuggestions = []
        store.deleteProfile()
        notice = "All learned writing data was deleted."
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
        guard accessibility.replace(suggestion, with: replacement, in: captured) else {
            notice = "The paragraph changed, so this suggestion was not applied."
            return
        }

        learner.record(outcome: outcome, for: suggestion, profile: &profile)
        saveProfile()
        undoInfo = UndoInfo(
            applicationBundleID: captured.applicationBundleID,
            range: suggestion.range,
            original: suggestion.originalText,
            replacement: replacement
        )
        updateStateAfterApplying(suggestion, replacement: replacement, in: captured)
        notice = outcome == .edited ? "Your edit was applied." : "Suggestion applied."
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
            elementFrame: captured.elementFrame
        )
        lastPromptedParagraph = correctedParagraph
        lastObservedText = correctedParagraph
        pendingSnapshot = correctedParagraph
        lastChangedAt = Date()
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
        permissionTrusted = AccessibilityService.Permission.isTrusted
        guard permissionTrusted else {
            statusMessage = "Accessibility permission required"
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
            return
        }
        guard settings.approvedBundleIDs.contains(bundleID) else {
            statusMessage = "Blocked in this application"
            resetCaptureSession()
            return
        }
        guard let captured = accessibility.focusedParagraph(for: frontmost) else {
            statusMessage = "No supported text field"
            return
        }

        currentCapture = captured
        statusMessage = "Learning in \(captured.applicationName)"
        let key = "\(captured.applicationBundleID):\(captured.paragraphRange.location)"
        if key != contextKey {
            contextKey = key
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
            let diff = diffEngine.diff(before: snapshot, after: captured.paragraph)
            if diff.isMeaningful && captured.applicationBundleID != "com.apple.Terminal" {
                // Terminal exposes a changing rendered screen buffer, not a
                // document edit history. Analyzing it is useful, but learning
                // from its diffs would pollute the personal writing profile.
                learner.learn(
                    from: diff,
                    in: snapshot,
                    fullAfter: captured.paragraph,
                    profile: &profile,
                    applicationBundleID: captured.applicationBundleID
                )
                saveProfile()
            }
        }

        // Offer help automatically once per stable paragraph. This also runs
        // when the paragraph was already complete when WriteSense started.
        if lastPromptedParagraph != captured.paragraph {
            lastPromptedParagraph = captured.paragraph
            let analysis = languageEngine.analyze(captured.paragraph, profile: profile, applicationBundleID: captured.applicationBundleID)
            if !analysis.suggestions.isEmpty {
                lastReviewLanguage = analysis.language
                latestSuggestions = analysis.suggestions
                floatingPanel.show(near: captured.elementFrame)
            }
        }

        pendingSnapshot = captured.paragraph
        self.lastChangedAt = Date()
    }

    private func captureApprovedParagraph() -> CapturedParagraph? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleID = application.bundleIdentifier,
              settings.approvedBundleIDs.contains(bundleID) else { return nil }
        return accessibility.focusedParagraph(for: application)
    }

    private func resetCaptureSession() {
        pendingSnapshot = nil
        lastObservedText = nil
        lastChangedAt = nil
        contextKey = nil
        currentCapture = nil
        lastPromptedParagraph = nil
        floatingPanel.hide()
    }

    private func updateStatus() {
        if !permissionTrusted {
            statusMessage = "Accessibility permission required"
        } else if !isLearningActive {
            statusMessage = "Learning is paused"
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

    private func saveProfile() {
        store.save(profile: profile)
    }
}

private struct UndoInfo {
    let applicationBundleID: String
    let range: TextRange
    let original: String
    let replacement: String
}
