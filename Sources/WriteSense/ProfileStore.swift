import CryptoKit
import Foundation
import Security

private enum SecureStorageError: LocalizedError {
    case missingEncryptionKey
    case encryptionFailed
    case unsupportedSchema(Int)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingEncryptionKey:
            return "The encryption key for local writing data is unavailable."
        case .encryptionFailed:
            return "WriteSense could not encrypt local writing data."
        case .unsupportedSchema(let version):
            return "Local data uses unsupported schema version \(version)."
        case .keychain(let status):
            return "The macOS Keychain returned error \(status)."
        }
    }
}

private final class KeychainEncryptionKeyProvider {
    private let service: String
    private let legacyServices: [String]
    private let account = "local-data-key-v1"

    init(service: String, legacyServices: [String] = []) {
        self.service = service
        self.legacyServices = legacyServices
    }

    func loadKey() throws -> SymmetricKey? {
        try loadKey(service: service)
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKey() { return existing }

        for legacyService in legacyServices {
            if let legacyKey = try loadKey(service: legacyService) {
                return try store(legacyKey, service: service)
            }
        }

        return try store(SymmetricKey(size: .bits256), service: service)
    }

    func deleteKey() throws {
        var firstError: SecureStorageError?
        for candidateService in Set([service] + legacyServices) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: candidateService,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound, firstError == nil {
                firstError = .keychain(status)
            }
        }
        if let firstError { throw firstError }
    }

    private func loadKey(service: String) throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureStorageError.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    private func store(_ key: SymmetricKey, service: String) throws -> SymmetricKey {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: keyData
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem,
           let existing = try loadKey(service: service) {
            return existing
        }
        guard status == errSecSuccess else { throw SecureStorageError.keychain(status) }
        return key
    }
}

final class ProfileStore {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let directory: URL
    private let profileURL: URL
    private let settingsURL: URL
    private let historyURL: URL
    private let runMarkerURL: URL
    private let legacyProfileURL: URL
    private let legacySettingsURL: URL
    private let keyProvider: KeychainEncryptionKeyProvider

    private(set) var lastErrorMessage: String?
    private(set) var lastRecoveryMessage: String?
    private(set) var recoveredFileNames: Set<String> = []
    private(set) var hasLoadFailure = false
    private let currentSchemaVersion = 2

    init(
        directoryURL: URL? = nil,
        keychainService: String = "io.andura.writesense.secure-storage"
    ) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let applicationSupport = directoryURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("WriteSense", isDirectory: true)
        directory = applicationSupport
        profileURL = applicationSupport.appendingPathComponent("writing-profile.enc")
        settingsURL = applicationSupport.appendingPathComponent("settings.enc")
        historyURL = applicationSupport.appendingPathComponent("writing-history.enc")
        runMarkerURL = applicationSupport.appendingPathComponent("run-state.json")
        legacyProfileURL = applicationSupport.appendingPathComponent("writing-profile.json")
        legacySettingsURL = applicationSupport.appendingPathComponent("settings.json")
        let legacyKeychainServices = keychainService == "io.andura.writesense.secure-storage"
            ? ["com.writesense.app.secure-storage"]
            : []
        keyProvider = KeychainEncryptionKeyProvider(
            service: keychainService,
            legacyServices: legacyKeychainServices
        )
        ensureDirectory()
    }

    func loadProfile() -> WritingProfile {
        load(
            WritingProfile.self,
            encryptedURL: profileURL,
            legacyURL: legacyProfileURL
        ) ?? .empty
    }

    @discardableResult
    func save(profile: WritingProfile) -> Bool {
        save(profile, to: profileURL)
    }

    func loadSettings() -> StoredSettings {
        load(
            StoredSettings.self,
            encryptedURL: settingsURL,
            legacyURL: legacySettingsURL
        ) ?? .defaults
    }

    @discardableResult
    func save(settings: StoredSettings) -> Bool {
        save(settings, to: settingsURL)
    }

    func loadHistory() -> WritingHistory {
        load(WritingHistory.self, encryptedURL: historyURL, legacyURL: nil) ?? .empty
    }

    @discardableResult
    func save(history: WritingHistory) -> Bool {
        save(history, to: historyURL)
    }

    func pruned(history: WritingHistory, retentionDays: Int, now: Date = Date()) -> WritingHistory {
        let activityCutoff = retentionDays > 0
            ? Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)
            : nil
        let diagnosticsCutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? .distantPast

        let corrections = activityCutoff.map { cutoff in
            history.correctionEvents.filter { $0.createdAt >= cutoff }
        } ?? []
        let suggestions = activityCutoff.map { cutoff in
            history.suggestionEvents.filter { $0.createdAt >= cutoff }
        } ?? []
        let sessions = activityCutoff.flatMap { cutoff in
            history.editingSessions?.filter { $0.lastUpdatedAt >= cutoff }
        }
        let audit = activityCutoff.flatMap { cutoff in
            history.privacyAuditEvents?.filter { $0.createdAt >= cutoff }
        }
        let diagnostics = history.diagnosticEvents?.filter { $0.createdAt >= diagnosticsCutoff }
        let compatibility = history.compatibilityObservations?.filter { $0.createdAt >= diagnosticsCutoff }
        let runs = history.applicationRuns?.filter { $0.startedAt >= diagnosticsCutoff }
        return WritingHistory(
            correctionEvents: Array(corrections.suffix(5_000)),
            suggestionEvents: Array(suggestions.suffix(10_000)),
            editingSessions: sessions.map { Array($0.suffix(5_000)) },
            privacyAuditEvents: audit.map { Array($0.suffix(2_000)) },
            diagnosticEvents: diagnostics.map { Array($0.suffix(10_000)) },
            compatibilityObservations: compatibility.map { Array($0.suffix(500)) },
            applicationRuns: runs.map { Array($0.suffix(200)) }
        )
    }

    func exportData(
        profile: WritingProfile,
        history: WritingHistory,
        settings: StoredSettings
    ) throws -> Data {
        let export = WriteSenseExport(
            formatVersion: 2,
            exportedAt: Date(),
            profile: profile,
            history: history,
            settings: settings
        )
        return try encoder.encode(export)
    }

    func beginApplicationRun(now: Date = Date()) -> RunStartResult? {
        ensureDirectory()
        let previous: ApplicationRunMarker?
        if let data = try? Data(contentsOf: runMarkerURL) {
            previous = try? decoder.decode(ApplicationRunMarker.self, from: data)
        } else {
            previous = nil
        }

        let current = ApplicationRunMarker(id: UUID(), startedAt: now)
        do {
            let data = try encoder.encode(current)
            try data.write(to: runMarkerURL, options: [.atomic])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: runMarkerURL.path)
            return RunStartResult(current: current, previousUnclean: previous)
        } catch {
            return nil
        }
    }

    func finishApplicationRun(_ id: UUID) {
        guard let data = try? Data(contentsOf: runMarkerURL),
              let marker = try? decoder.decode(ApplicationRunMarker.self, from: data),
              marker.id == id else { return }
        try? fileManager.removeItem(at: runMarkerURL)
    }

    @discardableResult
    func deleteAllData() -> Bool {
        var succeeded = true
        do {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            succeeded = false
        }

        do {
            try keyProvider.deleteKey()
        } catch {
            lastErrorMessage = error.localizedDescription
            succeeded = false
        }
        if succeeded {
            hasLoadFailure = false
            lastErrorMessage = nil
            lastRecoveryMessage = nil
            recoveredFileNames = []
        }
        return succeeded
    }

    private func load<T: Codable>(
        _ type: T.Type,
        encryptedURL: URL,
        legacyURL: URL?
    ) -> T? {
        if fileManager.fileExists(atPath: encryptedURL.path) {
            do {
                let encrypted = try Data(contentsOf: encryptedURL)
                guard let key = try keyProvider.loadKey() else {
                    throw SecureStorageError.missingEncryptionKey
                }
                let decoded: DecodedSecureValue<T> = try decodeSecureValue(
                    type,
                    from: encrypted,
                    using: key
                )
                if decoded.requiresMigration {
                    _ = save(decoded.value, to: encryptedURL)
                }
                return decoded.value
            } catch {
                let primaryError = error
                let backupURL = backupURL(for: encryptedURL)
                if let backup = try? Data(contentsOf: backupURL),
                   let key = (try? keyProvider.loadKey()) ?? nil,
                   let recovered: DecodedSecureValue<T> = try? decodeSecureValue(type, from: backup, using: key) {
                    do {
                        try backup.write(to: encryptedURL, options: [.atomic])
                        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: encryptedURL.path)
                        lastRecoveryMessage = "Recovered \(encryptedURL.lastPathComponent) from its encrypted backup."
                        recoveredFileNames.insert(encryptedURL.lastPathComponent)
                        return recovered.value
                    } catch {
                        lastErrorMessage = error.localizedDescription
                        hasLoadFailure = true
                        return nil
                    }
                }
                lastErrorMessage = primaryError.localizedDescription
                hasLoadFailure = true
                return nil
            }
        }

        guard let legacyURL,
              fileManager.fileExists(atPath: legacyURL.path) else { return nil }
        do {
            let legacyData = try Data(contentsOf: legacyURL)
            let decoded = try decoder.decode(type, from: legacyData)
            // One-time migration from the prototype's plaintext JSON files.
            // Remove plaintext only after its encrypted replacement is durable.
            if save(decoded, to: encryptedURL) {
                try? fileManager.removeItem(at: legacyURL)
            }
            return decoded
        } catch {
            lastErrorMessage = error.localizedDescription
            hasLoadFailure = true
            return nil
        }
    }

    private func decodeSecureValue<T: Codable>(
        _ type: T.Type,
        from encrypted: Data,
        using key: SymmetricKey
    ) throws -> DecodedSecureValue<T> {
        let box = try AES.GCM.SealedBox(combined: encrypted)
        let cleartext = try AES.GCM.open(box, using: key)
        if let envelope = try? decoder.decode(PersistedSecurePayload<T>.self, from: cleartext) {
            guard envelope.schemaVersion <= currentSchemaVersion else {
                throw SecureStorageError.unsupportedSchema(envelope.schemaVersion)
            }
            return DecodedSecureValue(value: envelope.payload, requiresMigration: envelope.schemaVersion < currentSchemaVersion)
        }
        // Version 1 encrypted files contained the Codable object directly.
        return DecodedSecureValue(value: try decoder.decode(type, from: cleartext), requiresMigration: true)
    }

    @discardableResult
    private func save<T: Codable>(_ value: T, to url: URL) -> Bool {
        guard !hasLoadFailure else { return false }
        do {
            ensureDirectory()
            let envelope = PersistedSecurePayload(schemaVersion: currentSchemaVersion, payload: value)
            let cleartext = try encoder.encode(envelope)
            let key = try keyProvider.loadOrCreateKey()
            let sealed = try AES.GCM.seal(cleartext, using: key)
            guard let combined = sealed.combined else { throw SecureStorageError.encryptionFailed }

            if let existing = try? Data(contentsOf: url) {
                let backup = backupURL(for: url)
                try existing.write(to: backup, options: [.atomic])
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
            try combined.write(to: url, options: [.atomic])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("backup")
    }

    private func ensureDirectory() {
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}

private struct PersistedSecurePayload<Payload: Codable>: Codable {
    let schemaVersion: Int
    let payload: Payload
}

private struct DecodedSecureValue<Value> {
    let value: Value
    let requiresMigration: Bool
}

struct WriteSenseExport: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let profile: WritingProfile
    let history: WritingHistory
    let settings: StoredSettings
}

struct StoredSettings: Codable {
    var approvedBundleIDs: Set<String>
    var learningEnabled: Bool
    var capitalizationChecksEnabled: Bool
    var historyRetentionDays: Int
    var tonePreference: TonePreference
    var onboardingCompleted: Bool
    var customApplicationNames: [String: String]
    var diagnosticsEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case approvedBundleIDs
        case learningEnabled
        case capitalizationChecksEnabled
        case historyRetentionDays
        case tonePreference
        case onboardingCompleted
        case customApplicationNames
        case diagnosticsEnabled
    }

    init(
        approvedBundleIDs: Set<String>,
        learningEnabled: Bool,
        capitalizationChecksEnabled: Bool = true,
        historyRetentionDays: Int = 30,
        tonePreference: TonePreference = .preserveVoice,
        onboardingCompleted: Bool = false,
        customApplicationNames: [String: String] = [:],
        diagnosticsEnabled: Bool = false
    ) {
        self.approvedBundleIDs = approvedBundleIDs
        self.learningEnabled = learningEnabled
        self.capitalizationChecksEnabled = capitalizationChecksEnabled
        self.historyRetentionDays = historyRetentionDays
        self.tonePreference = tonePreference
        self.onboardingCompleted = onboardingCompleted
        self.customApplicationNames = customApplicationNames
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        approvedBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .approvedBundleIDs)
            ?? Self.defaults.approvedBundleIDs
        learningEnabled = try container.decodeIfPresent(Bool.self, forKey: .learningEnabled)
            ?? Self.defaults.learningEnabled
        capitalizationChecksEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .capitalizationChecksEnabled
        ) ?? true
        historyRetentionDays = try container.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? 30
        tonePreference = try container.decodeIfPresent(TonePreference.self, forKey: .tonePreference)
            ?? .preserveVoice
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        customApplicationNames = try container.decodeIfPresent(
            [String: String].self,
            forKey: .customApplicationNames
        ) ?? [:]
        diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? false
    }

    static let defaults = StoredSettings(
        approvedBundleIDs: Set(["com.apple.TextEdit", "com.apple.Notes", "com.apple.mail"]),
        learningEnabled: false,
        capitalizationChecksEnabled: true,
        historyRetentionDays: 30,
        tonePreference: .preserveVoice,
        onboardingCompleted: false,
        customApplicationNames: [:],
        diagnosticsEnabled: false
    )
}

enum PatternGeneralizer {
    private static let pastForms: [String: String] = [
        "send": "sent", "go": "went", "write": "wrote", "make": "made", "see": "saw",
        "take": "took", "come": "came", "run": "ran", "meet": "met", "buy": "bought",
        "choose": "chose", "eat": "ate", "leave": "left", "know": "knew", "do": "did",
        "have": "had", "is": "was", "are": "were"
    ]

    static func key(category: PatternCategory, before: String, after: String) -> String {
        let before = normalized(before)
        let after = normalized(after)

        switch category {
        case .verbTense:
            if pastForms[before] == after || (before.hasSuffix("e") && after == before + "d") || after == before + "ed" {
                return "verb_tense:base_to_past"
            }
            if pastForms[after] == before || (after.hasSuffix("e") && before == after + "d") || before == after + "ed" {
                return "verb_tense:past_to_base"
            }
            if after.hasSuffix("ing") { return "verb_tense:to_progressive" }
            if after.hasSuffix("en") || after.hasSuffix("ed") { return "verb_tense:to_participle" }
            return "verb_tense:\(wordShape(before))>\(wordShape(after))"
        case .agreement:
            let singularTargets: Set<String> = ["is", "was", "has", "does"]
            let pluralTargets: Set<String> = ["are", "were", "have", "do"]
            if singularTargets.contains(after) || (!before.hasSuffix("s") && after == before + "s") {
                return "agreement:to_singular"
            }
            if pluralTargets.contains(after) || (before.hasSuffix("s") && String(before.dropLast()) == after) {
                return "agreement:to_plural"
            }
            return "agreement:\(before)>\(after)"
        case .articleUsage:
            return "article:\(article(in: before))>\(article(in: after))"
        case .capitalization:
            return "capitalization:sentence_or_word"
        case .punctuation:
            return "punctuation:\(punctuation(in: before))>\(punctuation(in: after))"
        case .repeatedWords:
            return "repeated_words:remove_duplicate"
        case .spelling, .vocabulary:
            return "\(category.rawValue):\(before)>\(after)"
        case .concision:
            return "concision:remove_words"
        case .clarity, .style, .unknown:
            return "\(category.rawValue):\(before)>\(after)"
        }
    }

    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func article(in value: String) -> String {
        let words = value.split(separator: " ").map(String.init)
        return words.first(where: { ["a", "an", "the"].contains($0) }) ?? "none"
    }

    private static func punctuation(in value: String) -> String {
        let marks = value.unicodeScalars.filter {
            CharacterSet.punctuationCharacters.contains($0)
        }
        return marks.isEmpty ? "none" : String(String.UnicodeScalarView(marks))
    }

    private static func wordShape(_ value: String) -> String {
        if value.hasSuffix("ing") { return "ing" }
        if value.hasSuffix("ed") { return "ed" }
        if value.hasSuffix("s") { return "s" }
        return "base"
    }
}

final class PatternLearner {
    @discardableResult
    func learn(
        from diff: CorrectionDiff,
        in fullBefore: String,
        fullAfter: String,
        profile: inout WritingProfile,
        applicationBundleID: String,
        applicationName: String? = nil,
        sessionID: UUID = UUID(),
        createdAt: Date = Date()
    ) -> CorrectionEvent? {
        guard diff.isMeaningful else { return nil }
        let before = clean(diff.before)
        let after = clean(diff.after)
        guard !before.isEmpty || !after.isEmpty else { return nil }
        // Large pasted or rewritten passages are not useful reusable patterns
        // and should never become retained correction examples.
        guard before.count <= 280, after.count <= 280 else { return nil }

        let category = categorize(before: before, after: after, fullBefore: fullBefore, fullAfter: fullAfter)
        let generalizedKey = PatternGeneralizer.key(category: category, before: before, after: after)
        let now = createdAt

        let matchingIndex = profile.patterns.firstIndex { pattern in
            guard pattern.category == category else { return false }
            let existingKey = pattern.generalizedKey ?? PatternGeneralizer.key(
                category: pattern.category,
                before: pattern.exampleBefore,
                after: pattern.exampleAfter
            )
            return existingKey == generalizedKey
        }

        let patternID: UUID
        if let index = matchingIndex {
            var pattern = profile.patterns[index]
            pattern.occurrenceCount += 1
            pattern.lastObservedAt = now
            pattern.generalizedKey = generalizedKey
            if pattern.exampleApplicationBundleID == nil {
                pattern.exampleApplicationBundleID = pattern.applicationBundleID ?? applicationBundleID
            }
            pattern.applicationBundleID = pattern.applicationBundleID == applicationBundleID
                ? applicationBundleID
                : nil

            var examples = pattern.supportingExamples ?? []
            let isNewExample = !pattern.allExamples.contains {
                clean($0.before).caseInsensitiveCompare(before) == .orderedSame &&
                    clean($0.after).caseInsensitiveCompare(after) == .orderedSame
            }
            if isNewExample {
                examples.insert(PatternExample(
                    before: before,
                    after: after,
                    observedAt: now,
                    applicationBundleID: applicationBundleID
                ), at: 0)
                pattern.supportingExamples = Array(examples.prefix(5))
            }
            pattern.description = description(for: category, pattern: pattern)
            pattern.confidence = confidence(for: pattern)
            profile.patterns[index] = pattern
            patternID = pattern.id
        } else {
            let pattern = LearnedPattern(
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
                applicationBundleID: applicationBundleID,
                generalizedKey: generalizedKey,
                supportingExamples: [],
                exampleApplicationBundleID: applicationBundleID
            )
            profile.patterns.append(pattern)
            patternID = pattern.id
        }

        applyConflictPenalty(before: before, after: after, category: category, excluding: patternID, profile: &profile)

        if category == .vocabulary,
           let pattern = profile.patterns.first(where: { $0.id == patternID }),
           pattern.occurrenceCount >= 2,
           after.split(separator: " ").count <= 3,
           !after.isEmpty {
            let term = after.lowercased()
            profile.vocabulary.insert(term)
            var sources = profile.vocabularySources ?? [:]
            sources[term, default: []].insert(applicationBundleID)
            profile.vocabularySources = sources
        }
        profile.updatedAt = now

        return CorrectionEvent(
            sessionID: sessionID,
            applicationName: applicationName ?? applicationBundleID,
            applicationBundleID: applicationBundleID,
            changedFragmentBefore: before,
            changedFragmentAfter: after,
            classification: classification(for: diff, category: category),
            category: category,
            patternID: patternID,
            createdAt: now
        )
    }

    func record(
        outcome: SuggestionOutcome,
        for suggestion: Suggestion,
        profile: inout WritingProfile,
        applicationBundleID: String? = nil
    ) {
        if outcome == .accepted || outcome == .edited { profile.acceptedSuggestionCount += 1 }
        if outcome == .rejected { profile.rejectedSuggestionCount += 1 }
        if outcome == .accepted || outcome == .edited || outcome == .rejected {
            updatePreference(
                for: suggestion,
                applicationBundleID: applicationBundleID,
                acceptanceDelta: outcome == .accepted || outcome == .edited ? 1 : 0,
                rejectionDelta: outcome == .rejected ? 1 : 0,
                profile: &profile
            )
        }

        if let patternID = suggestion.patternID,
           let index = profile.patterns.firstIndex(where: { $0.id == patternID }) {
            if outcome == .accepted || outcome == .edited { profile.patterns[index].acceptanceCount += 1 }
            if outcome == .rejected { profile.patterns[index].rejectionCount += 1 }
            profile.patterns[index].confidence = confidence(for: profile.patterns[index])
        }
        profile.updatedAt = Date()
    }

    func undo(
        outcome: SuggestionOutcome,
        for suggestion: Suggestion,
        profile: inout WritingProfile,
        applicationBundleID: String? = nil
    ) {
        if outcome == .accepted || outcome == .edited {
            profile.acceptedSuggestionCount = max(0, profile.acceptedSuggestionCount - 1)
            updatePreference(
                for: suggestion,
                applicationBundleID: applicationBundleID,
                acceptanceDelta: -1,
                rejectionDelta: 0,
                profile: &profile
            )
        }
        if let patternID = suggestion.patternID,
           let index = profile.patterns.firstIndex(where: { $0.id == patternID }),
           outcome == .accepted || outcome == .edited {
            profile.patterns[index].acceptanceCount = max(0, profile.patterns[index].acceptanceCount - 1)
            profile.patterns[index].confidence = confidence(for: profile.patterns[index])
        }
        profile.updatedAt = Date()
    }

    func deletePattern(_ id: UUID, from profile: inout WritingProfile) {
        profile.patterns.removeAll { $0.id == id }
        profile.updatedAt = Date()
    }

    private func updatePreference(
        for suggestion: Suggestion,
        applicationBundleID: String?,
        acceptanceDelta: Int,
        rejectionDelta: Int,
        profile: inout WritingProfile
    ) {
        let key = PatternGeneralizer.key(
            category: suggestion.category,
            before: suggestion.originalText,
            after: suggestion.suggestedText
        )
        var preferences = profile.suggestionPreferences ?? []
        if let index = preferences.firstIndex(where: {
            $0.generalizedKey == key &&
                $0.category == suggestion.category &&
                $0.applicationBundleID == applicationBundleID
        }) {
            preferences[index].acceptanceCount = max(
                0,
                preferences[index].acceptanceCount + acceptanceDelta
            )
            preferences[index].rejectionCount = max(
                0,
                preferences[index].rejectionCount + rejectionDelta
            )
            preferences[index].lastUpdatedAt = Date()
        } else if acceptanceDelta > 0 || rejectionDelta > 0 {
            preferences.append(SuggestionPreference(
                generalizedKey: key,
                category: suggestion.category,
                applicationBundleID: applicationBundleID,
                acceptanceCount: max(0, acceptanceDelta),
                rejectionCount: max(0, rejectionDelta)
            ))
        }
        profile.suggestionPreferences = preferences
    }

    private func applyConflictPenalty(
        before: String,
        after: String,
        category: PatternCategory,
        excluding patternID: UUID,
        profile: inout WritingProfile
    ) {
        let conflictIndices = profile.patterns.indices.filter { index in
            let pattern = profile.patterns[index]
            return pattern.id != patternID && pattern.category == category &&
                clean(pattern.exampleBefore).caseInsensitiveCompare(after) == .orderedSame &&
                clean(pattern.exampleAfter).caseInsensitiveCompare(before) == .orderedSame
        }
        guard !conflictIndices.isEmpty else { return }

        if let current = profile.patterns.firstIndex(where: { $0.id == patternID }) {
            profile.patterns[current].confidence = max(0.1, profile.patterns[current].confidence - 0.18)
        }
        for index in conflictIndices {
            profile.patterns[index].confidence = max(0.1, profile.patterns[index].confidence - 0.18)
        }
    }

    private func categorize(before: String, after: String, fullBefore: String, fullAfter: String) -> PatternCategory {
        let beforeLower = before.lowercased()
        let afterLower = after.lowercased()
        if beforeLower == afterLower && before != after { return .capitalization }
        if containsOnlyPunctuation(before) || containsOnlyPunctuation(after) { return .punctuation }

        let articles: Set<String> = ["a", "an", "the"]
        if articles.contains(beforeLower) || articles.contains(afterLower) { return .articleUsage }

        let commonCorrections: [String: String] = [
            "yu": "you", "teh": "the", "recieve": "receive", "seperate": "separate",
            "definately": "definitely", "adress": "address", "wich": "which", "becuase": "because"
        ]
        if commonCorrections[beforeLower] == afterLower { return .spelling }

        if afterLower.isEmpty,
           !beforeLower.isEmpty,
           fullBefore.range(
               of: #"\b"# + NSRegularExpression.escapedPattern(for: beforeLower) + #"\s+"# + NSRegularExpression.escapedPattern(for: beforeLower) + #"\b"#,
               options: [.regularExpression, .caseInsensitive]
           ) != nil {
            return .repeatedWords
        }

        if beforeLower.isEmpty || afterLower.isEmpty {
            if fullBefore.count > fullAfter.count + 8 { return .concision }
            return .vocabulary
        }

        let tenseWords: Set<String> = [
            "send", "sent", "go", "went", "write", "wrote", "make", "made", "see", "saw",
            "take", "took", "come", "came", "run", "ran", "meet", "met", "buy", "bought",
            "choose", "chose", "eat", "ate", "leave", "left", "know", "knew"
        ]
        if tenseWords.contains(beforeLower) || tenseWords.contains(afterLower) ||
            (afterLower.hasSuffix("ed") && !beforeLower.hasSuffix("ed")) {
            return .verbTense
        }

        let agreementWords: Set<String> = ["is", "are", "has", "have", "do", "does", "was", "were"]
        if agreementWords.contains(beforeLower) || agreementWords.contains(afterLower) ||
            afterLower == beforeLower + "s" ||
            (beforeLower.hasSuffix("s") && String(beforeLower.dropLast()) == afterLower) {
            return .agreement
        }

        if fullBefore.count > fullAfter.count + 8 { return .concision }
        if before.range(of: #"\s"#, options: .regularExpression) != nil ||
            after.range(of: #"\s"#, options: .regularExpression) != nil {
            return .style
        }
        return .vocabulary
    }

    private func classification(for diff: CorrectionDiff, category: PatternCategory) -> EditClassification {
        if diff.classification == .insertion || diff.classification == .deletion || diff.classification == .wordOrder {
            return diff.classification
        }
        switch category {
        case .punctuation: return .punctuation
        case .capitalization: return .capitalization
        case .verbTense, .agreement, .articleUsage, .repeatedWords: return .grammar
        case .concision, .style, .clarity: return .style
        case .vocabulary, .spelling: return .vocabulary
        case .unknown: return diff.classification
        }
    }

    private func description(for category: PatternCategory, before: String, after: String) -> String {
        switch category {
        case .verbTense: return "You repeatedly adjust verb tense in similar contexts."
        case .agreement: return "You repeatedly correct subject–verb agreement."
        case .articleUsage: return "You repeatedly adjust article usage."
        case .concision: return "You often make phrases more concise."
        case .capitalization: return "You repeatedly correct capitalization."
        case .punctuation: return "You repeatedly adjust punctuation."
        case .style: return "A recurring personal style edit: ‘\(before)’ → ‘\(after)’."
        default: return "You often change ‘\(before)’ to ‘\(after)’."
        }
    }

    private func description(for category: PatternCategory, pattern: LearnedPattern) -> String {
        if pattern.occurrenceCount > 1 {
            switch category {
            case .verbTense: return "You corrected verb tense \(pattern.occurrenceCount) times."
            case .agreement: return "You corrected agreement \(pattern.occurrenceCount) times."
            case .articleUsage: return "You adjusted article usage \(pattern.occurrenceCount) times."
            case .concision: return "You made similar phrases more concise \(pattern.occurrenceCount) times."
            case .capitalization: return "You corrected capitalization \(pattern.occurrenceCount) times."
            case .punctuation: return "You adjusted punctuation \(pattern.occurrenceCount) times."
            default: break
            }
        }
        return description(for: category, before: pattern.exampleBefore, after: pattern.exampleAfter)
    }

    private func confidence(for pattern: LearnedPattern) -> Double {
        let evidence = min(0.42, Double(pattern.occurrenceCount) * 0.12)
        let feedbackTotal = pattern.acceptanceCount + pattern.rejectionCount
        let feedback = feedbackTotal == 0
            ? 0
            : (Double(pattern.acceptanceCount - pattern.rejectionCount) / Double(feedbackTotal)) * 0.18
        return min(0.99, max(0.1, 0.35 + evidence + feedback))
    }

    private func containsOnlyPunctuation(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
