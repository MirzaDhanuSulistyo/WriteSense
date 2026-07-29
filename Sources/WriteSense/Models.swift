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

    var isReliable: Bool {
        enabled && occurrenceCount >= 2 && confidence >= 0.55
    }

    var acceptanceRate: Double {
        let total = acceptanceCount + rejectionCount
        guard total > 0 else { return 0 }
        return Double(acceptanceCount) / Double(total)
    }
}

struct WritingProfile: Codable {
    var patterns: [LearnedPattern] = []
    var vocabulary: Set<String> = []
    var acceptedSuggestionCount = 0
    var rejectedSuggestionCount = 0
    var updatedAt = Date()

    static let empty = WritingProfile()
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
}

struct CorrectionDiff {
    let before: String
    let after: String
    let isMeaningful: Bool
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
