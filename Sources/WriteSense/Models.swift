import Foundation
import ApplicationServices

struct TextRange: Codable, Equatable, Hashable {
    var location: Int
    var length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

enum PatternCategory: String, Codable, CaseIterable, Identifiable {
    case verbTense = "verb_tense"
    case agreement = "agreement"
    case articleUsage = "article_usage"
    case repeatedWords = "repeated_words"
    case spelling = "spelling"
    case punctuation = "punctuation"
    case capitalization = "capitalization"
    case clarity = "clarity"
    case vocabulary = "vocabulary"
    case concision = "concision"
    case style = "style"
    case unknown = "unknown"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verbTense: return "Verb tense"
        case .agreement: return "Subject–verb agreement"
        case .articleUsage: return "Article usage"
        case .repeatedWords: return "Repeated words"
        case .spelling: return "Spelling"
        case .punctuation: return "Punctuation"
        case .capitalization: return "Capitalization"
        case .clarity: return "Needs clarification"
        case .vocabulary: return "Vocabulary"
        case .concision: return "Concision"
        case .style: return "Style preference"
        case .unknown: return "Writing pattern"
        }
    }
}

enum EditClassification: String, Codable, CaseIterable {
    case insertion
    case deletion
    case replacement
    case wordOrder = "word_order"
    case punctuation
    case capitalization
    case grammar
    case style
    case vocabulary
    case unknown

    var title: String {
        switch self {
        case .insertion: return "Insertion"
        case .deletion: return "Deletion"
        case .replacement: return "Replacement"
        case .wordOrder: return "Word order"
        case .punctuation: return "Punctuation"
        case .capitalization: return "Capitalization"
        case .grammar: return "Grammar"
        case .style: return "Style"
        case .vocabulary: return "Vocabulary"
        case .unknown: return "Edit"
        }
    }
}

enum CorrectionSource: String, Codable {
    case manualUserEdit = "manual_user_edit"
    case acceptedSuggestion = "accepted_suggestion"
    case editedSuggestion = "edited_suggestion"
}

enum SuggestionOutcome: String, Codable {
    case accepted
    case rejected
    case edited
    case ignored
    case undone
}

enum TonePreference: String, Codable, CaseIterable, Identifiable {
    case preserveVoice = "preserve_voice"
    case neutral
    case formal
    case concise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preserveVoice: return "Preserve my voice"
        case .neutral: return "Neutral"
        case .formal: return "Formal"
        case .concise: return "Concise"
        }
    }
}

struct PatternExample: Codable, Equatable, Identifiable {
    let id: UUID
    var before: String
    var after: String
    var observedAt: Date
    var applicationBundleID: String?

    init(
        id: UUID = UUID(),
        before: String,
        after: String,
        observedAt: Date = Date(),
        applicationBundleID: String? = nil
    ) {
        self.id = id
        self.before = before
        self.after = after
        self.observedAt = observedAt
        self.applicationBundleID = applicationBundleID
    }
}

struct LearnedPattern: Codable, Identifiable, Equatable {
    let id: UUID
    var category: PatternCategory
    var description: String
    var exampleBefore: String
    var exampleAfter: String
    var occurrenceCount: Int
    var acceptanceCount: Int
    var rejectionCount: Int
    var confidence: Double
    var enabled: Bool
    var lastObservedAt: Date
    var applicationBundleID: String?

    // Optional fields preserve compatibility with profiles created before
    // generalized pattern clustering and supporting examples were introduced.
    var generalizedKey: String?
    var supportingExamples: [PatternExample]?
    var exampleApplicationBundleID: String? = nil

    var isReliable: Bool {
        enabled && occurrenceCount >= 2 && confidence >= 0.55
    }

    var acceptanceRate: Double {
        let total = acceptanceCount + rejectionCount
        guard total > 0 else { return 0 }
        return Double(acceptanceCount) / Double(total)
    }

    var allExamples: [PatternExample] {
        let primary = PatternExample(
            id: id,
            before: exampleBefore,
            after: exampleAfter,
            observedAt: lastObservedAt,
            applicationBundleID: exampleApplicationBundleID ?? applicationBundleID
        )
        let additional = supportingExamples ?? []
        return [primary] + additional.filter {
            $0.before.caseInsensitiveCompare(exampleBefore) != .orderedSame ||
                $0.after.caseInsensitiveCompare(exampleAfter) != .orderedSame
        }
    }
}

struct SuggestionPreference: Codable, Identifiable, Equatable {
    let id: UUID
    var generalizedKey: String
    var category: PatternCategory
    var applicationBundleID: String?
    var acceptanceCount: Int
    var rejectionCount: Int
    var lastUpdatedAt: Date

    init(
        id: UUID = UUID(),
        generalizedKey: String,
        category: PatternCategory,
        applicationBundleID: String?,
        acceptanceCount: Int = 0,
        rejectionCount: Int = 0,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.generalizedKey = generalizedKey
        self.category = category
        self.applicationBundleID = applicationBundleID
        self.acceptanceCount = acceptanceCount
        self.rejectionCount = rejectionCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct WritingProfile: Codable {
    var patterns: [LearnedPattern] = []
    var vocabulary: Set<String> = []
    var acceptedSuggestionCount = 0
    var rejectedSuggestionCount = 0
    var updatedAt = Date()
    var vocabularySources: [String: Set<String>]? = nil
    var suggestionPreferences: [SuggestionPreference]? = nil

    static let empty = WritingProfile()
}

struct CorrectionEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    var applicationName: String
    var applicationBundleID: String
    var changedFragmentBefore: String
    var changedFragmentAfter: String
    var classification: EditClassification
    var category: PatternCategory
    var source: CorrectionSource
    var patternID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        applicationName: String,
        applicationBundleID: String,
        changedFragmentBefore: String,
        changedFragmentAfter: String,
        classification: EditClassification,
        category: PatternCategory,
        source: CorrectionSource = .manualUserEdit,
        patternID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.applicationName = applicationName
        self.applicationBundleID = applicationBundleID
        self.changedFragmentBefore = changedFragmentBefore
        self.changedFragmentAfter = changedFragmentAfter
        self.classification = classification
        self.category = category
        self.source = source
        self.patternID = patternID
        self.createdAt = createdAt
    }
}

struct SuggestionFeedbackEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var category: PatternCategory
    var outcome: SuggestionOutcome
    var wasPersonalized: Bool
    var patternID: UUID?
    var applicationBundleID: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        category: PatternCategory,
        outcome: SuggestionOutcome,
        wasPersonalized: Bool,
        patternID: UUID?,
        applicationBundleID: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.outcome = outcome
        self.wasPersonalized = wasPersonalized
        self.patternID = patternID
        self.applicationBundleID = applicationBundleID
        self.createdAt = createdAt
    }
}

struct EditingSessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var applicationName: String
    var applicationBundleID: String
    var startedAt: Date
    var lastUpdatedAt: Date
    var endedAt: Date?
    var correctionCount: Int

    init(
        id: UUID,
        applicationName: String,
        applicationBundleID: String,
        startedAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        endedAt: Date? = nil,
        correctionCount: Int = 0
    ) {
        self.id = id
        self.applicationName = applicationName
        self.applicationBundleID = applicationBundleID
        self.startedAt = startedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.endedAt = endedAt
        self.correctionCount = correctionCount
    }
}

enum PrivacyAuditAction: String, Codable {
    case accessibilityRequested = "accessibility_requested"
    case learningEnabled = "learning_enabled"
    case learningDisabled = "learning_disabled"
    case applicationApproved = "application_approved"
    case applicationRevoked = "application_revoked"
    case secureFieldBlocked = "secure_field_blocked"
    case privateContextBlocked = "private_context_blocked"
    case dataExported = "data_exported"
    case todayDataDeleted = "today_data_deleted"
    case applicationDataDeleted = "application_data_deleted"
    case personalizationReset = "personalization_reset"
}

struct PrivacyAuditEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var action: PrivacyAuditAction
    var applicationBundleID: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        action: PrivacyAuditAction,
        applicationBundleID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.applicationBundleID = applicationBundleID
        self.createdAt = createdAt
    }
}

struct WritingHistory: Codable, Equatable {
    var correctionEvents: [CorrectionEvent]
    var suggestionEvents: [SuggestionFeedbackEvent]
    var editingSessions: [EditingSessionRecord]?
    var privacyAuditEvents: [PrivacyAuditEvent]?
    var diagnosticEvents: [DiagnosticEvent]?
    var compatibilityObservations: [CompatibilityObservation]?
    var applicationRuns: [ApplicationRunRecord]?

    init(
        correctionEvents: [CorrectionEvent] = [],
        suggestionEvents: [SuggestionFeedbackEvent] = [],
        editingSessions: [EditingSessionRecord]? = nil,
        privacyAuditEvents: [PrivacyAuditEvent]? = nil,
        diagnosticEvents: [DiagnosticEvent]? = nil,
        compatibilityObservations: [CompatibilityObservation]? = nil,
        applicationRuns: [ApplicationRunRecord]? = nil
    ) {
        self.correctionEvents = correctionEvents
        self.suggestionEvents = suggestionEvents
        self.editingSessions = editingSessions
        self.privacyAuditEvents = privacyAuditEvents
        self.diagnosticEvents = diagnosticEvents
        self.compatibilityObservations = compatibilityObservations
        self.applicationRuns = applicationRuns
    }

    static let empty = WritingHistory()
}

struct Suggestion: Identifiable, Equatable {
    let id: UUID
    var originalText: String
    var suggestedText: String
    var category: PatternCategory
    var explanation: String
    var confidence: Double
    var range: TextRange
    var isPersonalized: Bool = false
    var personalizationReason: String?
    var patternID: UUID?
    var alternativeTexts: [String] = []

    var requiresClarification: Bool { !alternativeTexts.isEmpty }

    init(
        id: UUID = UUID(),
        originalText: String,
        suggestedText: String,
        category: PatternCategory,
        explanation: String,
        confidence: Double,
        range: TextRange,
        isPersonalized: Bool = false,
        personalizationReason: String? = nil,
        patternID: UUID? = nil,
        alternativeTexts: [String] = []
    ) {
        self.id = id
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.category = category
        self.explanation = explanation
        self.confidence = confidence
        self.range = range
        self.isPersonalized = isPersonalized
        self.personalizationReason = personalizationReason
        self.patternID = patternID
        self.alternativeTexts = alternativeTexts
    }
}

struct CapturedParagraph {
    let applicationName: String
    let applicationBundleID: String
    let fullText: String
    let paragraph: String
    let paragraphRange: TextRange
    let element: AXUIElement
    let elementFrame: CGRect?
    let isWritable: Bool
}

struct CorrectionDiff: Equatable {
    let before: String
    let after: String
    let isMeaningful: Bool
    let classification: EditClassification

    init(
        before: String,
        after: String,
        isMeaningful: Bool,
        classification: EditClassification = .unknown
    ) {
        self.before = before
        self.after = after
        self.isMeaningful = isMeaningful
        self.classification = classification
    }
}

struct SupportedApplication: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String

    var isSensitiveByDefault: Bool {
        ["com.apple.Terminal", "com.apple.keychainaccess"].contains(bundleID)
    }

    var isSuggestionOnly: Bool {
        bundleID == "com.apple.Terminal"
    }

    static let defaults: [SupportedApplication] = [
        SupportedApplication(id: "textedit", name: "TextEdit", bundleID: "com.apple.TextEdit"),
        SupportedApplication(id: "notes", name: "Notes", bundleID: "com.apple.Notes"),
        SupportedApplication(id: "mail", name: "Mail", bundleID: "com.apple.mail"),
        SupportedApplication(id: "safari", name: "Safari", bundleID: "com.apple.Safari"),
        SupportedApplication(id: "chrome", name: "Google Chrome", bundleID: "com.google.Chrome"),
        SupportedApplication(id: "terminal", name: "Terminal", bundleID: "com.apple.Terminal")
    ]
}
