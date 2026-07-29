import Foundation

final class ProfileStore {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let profileURL: URL
    private let settingsURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = applicationSupport.appendingPathComponent("WriteSense", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        profileURL = directory.appendingPathComponent("writing-profile.json")
        settingsURL = directory.appendingPathComponent("settings.json")
    }

    func loadProfile() -> WritingProfile {
        guard let data = try? Data(contentsOf: profileURL),
              let profile = try? decoder.decode(WritingProfile.self, from: data) else {
            return .empty
        }
        return profile
    }

    func save(profile: WritingProfile) {
        guard let data = try? encoder.encode(profile) else { return }
        try? data.write(to: profileURL, options: .atomic)
    }

    func loadSettings() -> StoredSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(StoredSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    func save(settings: StoredSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    func deleteProfile() {
        try? fileManager.removeItem(at: profileURL)
    }
}

struct StoredSettings: Codable {
    var approvedBundleIDs: Set<String>
    var learningEnabled: Bool

    static let defaults = StoredSettings(
        approvedBundleIDs: Set(["com.apple.TextEdit", "com.apple.Notes", "com.apple.mail"]),
        learningEnabled: false
    )
}

final class PatternLearner {
    func learn(from diff: CorrectionDiff, in fullBefore: String, fullAfter: String, profile: inout WritingProfile, applicationBundleID: String) {
        guard diff.isMeaningful else { return }
        let before = clean(diff.before)
        let after = clean(diff.after)
        guard !before.isEmpty || !after.isEmpty else { return }

        let category = categorize(before: before, after: after, fullBefore: fullBefore, fullAfter: fullAfter)
        let signature = makeSignature(category: category, before: before, after: after)
        let now = Date()

        if let index = profile.patterns.firstIndex(where: {
            makeSignature(category: $0.category, before: $0.exampleBefore, after: $0.exampleAfter) == signature
        }) {
            var pattern = profile.patterns[index]
            pattern.occurrenceCount += 1
            pattern.lastObservedAt = now
            pattern.applicationBundleID = pattern.applicationBundleID == applicationBundleID ? applicationBundleID : nil
            pattern.confidence = confidence(for: pattern)
            profile.patterns[index] = pattern
        } else {
            profile.patterns.append(LearnedPattern(
                id: UUID(),
                category: category,
                description: description(for: category, before: before, after: after),
                exampleBefore: before,
                exampleAfter: after,
                occurrenceCount: 1,
                acceptanceCount: 0,
                rejectionCount: 0,
                confidence: 0.35,
                enabled: true,
                lastObservedAt: now,
                applicationBundleID: applicationBundleID
            ))
        }

        // A replacement of one unfamiliar word is a useful vocabulary signal,
        // but only store the word, never the surrounding paragraph.
        if category == .vocabulary, after.split(separator: " ").count <= 3 {
            profile.vocabulary.insert(after.lowercased())
        }
        profile.updatedAt = now
    }

    func record(outcome: SuggestionOutcome, for suggestion: Suggestion, profile: inout WritingProfile) {
        if outcome == .accepted { profile.acceptedSuggestionCount += 1 }
        if outcome == .rejected { profile.rejectedSuggestionCount += 1 }
        guard let patternID = suggestion.patternID,
              let index = profile.patterns.firstIndex(where: { $0.id == patternID }) else {
            profile.updatedAt = Date()
            return
        }

        if outcome == .accepted { profile.patterns[index].acceptanceCount += 1 }
        if outcome == .rejected { profile.patterns[index].rejectionCount += 1 }
        profile.patterns[index].confidence = confidence(for: profile.patterns[index])
        profile.updatedAt = Date()
    }

    func deletePattern(_ id: UUID, from profile: inout WritingProfile) {
        profile.patterns.removeAll { $0.id == id }
        profile.updatedAt = Date()
    }

    private func categorize(before: String, after: String, fullBefore: String, fullAfter: String) -> PatternCategory {
        let b = before.lowercased()
        let a = after.lowercased()
        if b.isEmpty || a.isEmpty { return .vocabulary }
        if ["send", "go", "write", "make", "see", "take", "come", "run", "meet", "buy", "choose", "eat"].contains(b) {
            return .verbTense
        }
        if ["sent", "went", "wrote", "made", "saw", "took", "came", "ran", "met", "bought", "chose", "ate"].contains(a) {
            return .verbTense
        }
        if ["is", "are", "has", "have", "do", "does", "was", "were"].contains(b) ||
            ["is", "are", "has", "have", "do", "does", "was", "were"].contains(a) {
            return .agreement
        }
        if b == "a" || a == "an" || b == "an" || a == "a" { return .articleUsage }
        if before.range(of: #"\s"#, options: .regularExpression) != nil || after.range(of: #"\s"#, options: .regularExpression) != nil {
            return .style
        }
        if fullBefore.count > fullAfter.count + 8 { return .concision }
        return .vocabulary
    }

    private func description(for category: PatternCategory, before: String, after: String) -> String {
        switch category {
        case .verbTense: return "You often change ‘\(before)’ to ‘\(after)’."
        case .agreement: return "You often adjust ‘\(before)’ to ‘\(after)’ for agreement."
        case .articleUsage: return "You prefer ‘\(after)’ instead of ‘\(before)’ in this context."
        case .concision: return "You often make this phrase more concise."
        case .style: return "A recurring personal style edit: ‘\(before)’ → ‘\(after)’."
        default: return "You often change ‘\(before)’ to ‘\(after)’."
        }
    }

    private func confidence(for pattern: LearnedPattern) -> Double {
        let evidence = min(0.36, Double(pattern.occurrenceCount) * 0.12)
        let feedbackTotal = pattern.acceptanceCount + pattern.rejectionCount
        let feedback = feedbackTotal == 0 ? 0 : (Double(pattern.acceptanceCount - pattern.rejectionCount) / Double(feedbackTotal)) * 0.18
        return min(0.99, max(0.1, 0.35 + evidence + feedback))
    }

    private func makeSignature(category: PatternCategory, before: String, after: String) -> String {
        "\(category.rawValue)|\(clean(before).lowercased())|\(clean(after).lowercased())"
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SuggestionOutcome {
    case accepted
    case rejected
    case edited
    case ignored
}
