import Foundation

enum DiagnosticOperation: String, Codable, CaseIterable {
    case localReview = "local_review"
    case deepReview = "deep_review"
    case diffGeneration = "diff_generation"
    case textReplacement = "text_replacement"
    case compatibilityCheck = "compatibility_check"
    case storageRecovery = "storage_recovery"
    case permissionUnavailable = "permission_unavailable"
    case permissionRestored = "permission_restored"
    case uncleanTermination = "unclean_termination"
    case secureContextBlocked = "secure_context_blocked"
}

enum DiagnosticErrorCode: String, Codable {
    case previousRunDidNotExitCleanly = "previous_run_did_not_exit_cleanly"
    case accessibilityPermissionMissing = "accessibility_permission_missing"
    case foundationModelError = "foundation_model_error"
    case paragraphTooLong = "paragraph_too_long"
    case undoReplacementFailed = "undo_replacement_failed"
    case staleOrUnsupportedRange = "stale_or_unsupported_range"
    case secureFieldBlocked = "secure_field_blocked"
    case privateContextBlocked = "private_context_blocked"
    case permissionRequired = "permission_required"
    case applicationNotApproved = "application_not_approved"
    case applicationUnavailable = "application_unavailable"
    case unsupportedField = "unsupported_field"
    case noFocusedField = "no_focused_field"
}

struct DiagnosticEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var operation: DiagnosticOperation
    var succeeded: Bool
    var durationMilliseconds: Double?
    var applicationBundleID: String?
    var errorCode: DiagnosticErrorCode?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        operation: DiagnosticOperation,
        succeeded: Bool,
        durationMilliseconds: Double? = nil,
        applicationBundleID: String? = nil,
        errorCode: DiagnosticErrorCode? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.operation = operation
        self.succeeded = succeeded
        self.durationMilliseconds = durationMilliseconds
        self.applicationBundleID = applicationBundleID
        self.errorCode = errorCode
        self.createdAt = createdAt
    }
}

struct ApplicationRunRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var cleanExit: Bool?

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        cleanExit: Bool? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.cleanExit = cleanExit
    }
}

enum CompatibilityResult: String, Codable, CaseIterable {
    case readWrite = "read_write"
    case readOnly = "read_only"
    case secureFieldBlocked = "secure_field_blocked"
    case privateContextBlocked = "private_context_blocked"
    case unsupportedField = "unsupported_field"
    case noFocusedField = "no_focused_field"
    case permissionRequired = "permission_required"
    case applicationNotApproved = "application_not_approved"
    case applicationUnavailable = "application_unavailable"

    var title: String {
        switch self {
        case .readWrite: return "Readable; replacement appears supported"
        case .readOnly: return "Review and Copy only"
        case .secureFieldBlocked: return "Secure field blocked"
        case .privateContextBlocked: return "Private context blocked"
        case .unsupportedField: return "Unsupported field"
        case .noFocusedField: return "No focused text field"
        case .permissionRequired: return "Accessibility permission required"
        case .applicationNotApproved: return "Application is not approved"
        case .applicationUnavailable: return "Application unavailable"
        }
    }

    var diagnosticErrorCode: DiagnosticErrorCode? {
        switch self {
        case .secureFieldBlocked: return .secureFieldBlocked
        case .privateContextBlocked: return .privateContextBlocked
        case .unsupportedField: return .unsupportedField
        case .noFocusedField: return .noFocusedField
        case .permissionRequired: return .permissionRequired
        case .applicationNotApproved: return .applicationNotApproved
        case .applicationUnavailable: return .applicationUnavailable
        case .readWrite, .readOnly: return nil
        }
    }

    var isSuccessfulSafetyResult: Bool {
        switch self {
        case .readWrite, .readOnly, .secureFieldBlocked, .privateContextBlocked:
            return true
        case .unsupportedField, .noFocusedField, .permissionRequired, .applicationNotApproved, .applicationUnavailable:
            return false
        }
    }
}

struct CompatibilityObservation: Codable, Identifiable, Equatable {
    let id: UUID
    var applicationName: String
    var applicationBundleID: String
    var result: CompatibilityResult
    var macOSVersion: String
    var applicationVersion: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        applicationName: String,
        applicationBundleID: String,
        result: CompatibilityResult,
        macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        applicationVersion: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.applicationName = applicationName
        self.applicationBundleID = applicationBundleID
        self.result = result
        self.macOSVersion = macOSVersion
        self.applicationVersion = applicationVersion
        self.createdAt = createdAt
    }
}

struct ApplicationRunMarker: Codable, Equatable {
    let id: UUID
    let startedAt: Date
}

struct RunStartResult {
    let current: ApplicationRunMarker
    let previousUnclean: ApplicationRunMarker?
}

struct DiagnosticsSummary: Codable, Equatable {
    var generatedAt: Date
    var appVersion: String
    var macOSVersion: String
    var completedRunCount: Int
    var uncleanRunCount: Int
    var crashFreeRunRate: Double?
    var averageLocalReviewMilliseconds: Double?
    var p95LocalReviewMilliseconds: Double?
    var replacementFailureCount: Int
    var permissionFailureCount: Int
    var secureContextBlockCount: Int
    var compatibilityCheckCount: Int
    var weeklyActiveDays: Int
    var retainedSuggestionAcceptanceRate: Double?

    static func make(from history: WritingHistory, now: Date = Date()) -> DiagnosticsSummary {
        let runs = (history.applicationRuns ?? []).filter { $0.cleanExit != nil }
        let unclean = runs.filter { $0.cleanExit == false }.count
        let crashFreeRate = runs.isEmpty ? nil : Double(runs.count - unclean) / Double(runs.count)

        let reviewDurations = (history.diagnosticEvents ?? [])
            .filter { $0.operation == .localReview && $0.succeeded }
            .compactMap(\.durationMilliseconds)
            .sorted()
        let average = reviewDurations.isEmpty
            ? nil
            : reviewDurations.reduce(0, +) / Double(reviewDurations.count)
        let p95: Double?
        if reviewDurations.isEmpty {
            p95 = nil
        } else {
            let index = min(reviewDurations.count - 1, Int(ceil(Double(reviewDurations.count) * 0.95)) - 1)
            p95 = reviewDurations[max(0, index)]
        }

        let diagnostics = history.diagnosticEvents ?? []
        let privacyAudit = history.privacyAuditEvents ?? []
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let activeDates = (history.editingSessions ?? []).map(\.startedAt) +
            (history.applicationRuns ?? []).map(\.startedAt)
        let activeDays = Set(activeDates
            .filter { $0 >= sevenDaysAgo }
            .map { Calendar.current.startOfDay(for: $0) })

        let feedback = history.suggestionEvents.filter {
            $0.outcome == .accepted || $0.outcome == .edited || $0.outcome == .rejected
        }
        let accepted = feedback.filter { $0.outcome == .accepted || $0.outcome == .edited }.count
        let acceptance = feedback.isEmpty ? nil : Double(accepted) / Double(feedback.count)

        return DiagnosticsSummary(
            generatedAt: now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            completedRunCount: runs.count,
            uncleanRunCount: unclean,
            crashFreeRunRate: crashFreeRate,
            averageLocalReviewMilliseconds: average,
            p95LocalReviewMilliseconds: p95,
            replacementFailureCount: diagnostics.filter {
                $0.operation == .textReplacement && !$0.succeeded
            }.count,
            permissionFailureCount: diagnostics.filter {
                $0.operation == .permissionUnavailable
            }.count,
            secureContextBlockCount: max(
                diagnostics.filter { $0.operation == .secureContextBlocked }.count,
                privacyAudit.filter {
                    $0.action == .secureFieldBlocked || $0.action == .privateContextBlocked
                }.count
            ),
            compatibilityCheckCount: (history.compatibilityObservations ?? []).count,
            weeklyActiveDays: activeDays.count,
            retainedSuggestionAcceptanceRate: acceptance
        )
    }
}

enum BetaFeedbackIssue: String, Codable, CaseIterable, Identifiable {
    case permissionSetup = "permission_setup"
    case unsupportedEditor = "unsupported_editor"
    case incorrectSuggestion = "incorrect_suggestion"
    case missedSuggestion = "missed_suggestion"
    case replacementFailed = "replacement_failed"
    case distractingPanel = "distracting_panel"
    case privacyConcern = "privacy_concern"
    case performance = "performance"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .permissionSetup: return "Permission setup"
        case .unsupportedEditor: return "Unsupported editor"
        case .incorrectSuggestion: return "Incorrect suggestion"
        case .missedSuggestion: return "Missed suggestion"
        case .replacementFailed: return "Replacement failed"
        case .distractingPanel: return "Suggestion panel was distracting"
        case .privacyConcern: return "Privacy or trust concern"
        case .performance: return "Performance or battery usage"
        case .other: return "Other"
        }
    }
}

struct BetaFeedbackReport: Codable {
    var formatVersion = 1
    var createdAt = Date()
    var usefulnessRating: Int
    var recommendationQualityRating: Int
    var trustRating: Int
    var keepLearningEnabled: Bool
    var issues: [BetaFeedbackIssue]
    var comments: String
    var diagnostics: DiagnosticsSummary?

    init(
        usefulnessRating: Int,
        recommendationQualityRating: Int,
        trustRating: Int,
        keepLearningEnabled: Bool,
        issues: [BetaFeedbackIssue],
        comments: String,
        diagnostics: DiagnosticsSummary?
    ) {
        self.usefulnessRating = usefulnessRating
        self.recommendationQualityRating = recommendationQualityRating
        self.trustRating = trustRating
        self.keepLearningEnabled = keepLearningEnabled
        self.issues = issues
        self.comments = comments
        self.diagnostics = diagnostics
    }
}

struct DiagnosticsExport: Codable {
    var formatVersion = 1
    var generatedAt = Date()
    var summary: DiagnosticsSummary
    var diagnosticEvents: [DiagnosticEvent]
    var compatibilityObservations: [CompatibilityObservation]
    var applicationRuns: [ApplicationRunRecord]
    var privacyAuditEvents: [PrivacyAuditEvent]

    static func make(from history: WritingHistory) -> DiagnosticsExport {
        DiagnosticsExport(
            summary: .make(from: history),
            diagnosticEvents: history.diagnosticEvents ?? [],
            compatibilityObservations: history.compatibilityObservations ?? [],
            applicationRuns: history.applicationRuns ?? [],
            privacyAuditEvents: history.privacyAuditEvents ?? []
        )
    }
}
