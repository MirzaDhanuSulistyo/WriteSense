import Foundation
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "A corrected English sentence")
struct EvaluationResult {
    @Guide(description: "The fully corrected sentence, preserving the original meaning")
    var correctedText: String

    @Guide(description: "A brief explanation of the grammatical correction")
    var explanation: String
}

struct EvaluationCase {
    let id: String
    let group: String
    let input: String
    let expected: String
}

@available(macOS 26.0, *)
@main
struct FoundationModelEvaluation {
    static func main() async {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            print("Apple Foundation Models unavailable: \(model.availability)")
            exit(2)
        }

        let cases = tenseCases + grammarCases
        var passed = 0
        var failed = 0

        for item in cases {
            do {
                let result = try await evaluate(item)
                if normalize(result.correctedText) == normalize(item.expected) {
                    passed += 1
                    print("PASS [\(item.group)] \(item.id)")
                } else {
                    failed += 1
                    print("FAIL [\(item.group)] \(item.id)")
                    print("  input:    \(item.input)")
                    print("  expected: \(item.expected)")
                    print("  actual:   \(result.correctedText)")
                    print("  reason:   \(result.explanation)")
                }
            } catch {
                failed += 1
                print("ERROR [\(item.group)] \(item.id): \(error.localizedDescription)")
            }
        }

        print("\nFoundation Models evaluation: \(passed) passed, \(failed) failed, \(cases.count) total")
        exit(failed == 0 ? 0 : 1)
    }

    private static func evaluate(_ item: EvaluationCase) async throws -> EvaluationResult {
        let session = LanguageModelSession(instructions: """
            You are an English grammar editor.
            Correct the supplied sentence while preserving its exact meaning and vocabulary whenever possible.
            Fix grammar, tense, agreement, articles, spelling, capitalization, punctuation, and unnecessary wording.
            Preserve the original timeframe, intended tense, and aspect. Never infer unstated past or future context.
            When an auxiliary tense construction is malformed, preserve its auxiliaries and repair the verb form instead of choosing another tense.
            For two explicitly completed past actions linked by “before,” use past perfect for the earlier action when appropriate.
            Use subject pronouns in compound subjects. Treat a capitalized family title after an imperative as direct address when punctuation makes that meaning sensible.
            Do not discuss alternatives. Always return the complete corrected sentence.
            """)
        let response = try await session.respond(
            to: "Correct this sentence: <sentence>\(item.input)</sentence>",
            generating: EvaluationResult.self,
            options: GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 220)
        )
        return response.content
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
    }

    private static let tenseCases: [EvaluationCase] = [
        EvaluationCase(id: "tense-present-simple", group: "present simple", input: "She go to work every day.", expected: "She goes to work every day."),
        EvaluationCase(id: "tense-present-continuous", group: "present continuous", input: "She are reading now.", expected: "She is reading now."),
        EvaluationCase(id: "tense-present-perfect", group: "present perfect", input: "She have finished the report.", expected: "She has finished the report."),
        EvaluationCase(id: "tense-present-perfect-continuous", group: "present perfect continuous", input: "She have been working for two hours.", expected: "She has been working for two hours."),
        EvaluationCase(id: "tense-past-simple", group: "past simple", input: "She go to work yesterday.", expected: "She went to work yesterday."),
        EvaluationCase(id: "tense-past-continuous", group: "past continuous", input: "She were reading at noon.", expected: "She was reading at noon."),
        EvaluationCase(id: "tense-past-perfect", group: "past perfect", input: "She has finished before the meeting started.", expected: "She had finished before the meeting started."),
        EvaluationCase(id: "tense-past-perfect-continuous", group: "past perfect continuous", input: "She has been working for two hours before lunch began.", expected: "She had been working for two hours before lunch began."),
        EvaluationCase(id: "tense-future-simple", group: "future simple", input: "She will goes tomorrow.", expected: "She will go tomorrow."),
        EvaluationCase(id: "tense-future-continuous", group: "future continuous", input: "She will be work at noon.", expected: "She will be working at noon."),
        EvaluationCase(id: "tense-future-perfect", group: "future perfect", input: "She will has finished by Friday.", expected: "She will have finished by Friday."),
        EvaluationCase(id: "tense-future-perfect-continuous", group: "future perfect continuous", input: "By noon, she will have been work for two hours.", expected: "By noon, she will have been working for two hours.")
    ]

    private static let grammarCases: [EvaluationCase] = [
        EvaluationCase(id: "grammar-agreement", group: "agreement", input: "The list of items are on the desk.", expected: "The list of items is on the desk."),
        EvaluationCase(id: "grammar-article", group: "article", input: "He bought a umbrella.", expected: "He bought an umbrella."),
        EvaluationCase(id: "grammar-missing-article", group: "missing article", input: "Please give me example.", expected: "Please give me an example."),
        EvaluationCase(id: "grammar-pronouns", group: "pronouns", input: "Me and her went home.", expected: "She and I went home."),
        EvaluationCase(id: "grammar-comparative", group: "comparative", input: "This option is more better.", expected: "This option is better."),
        EvaluationCase(id: "grammar-preposition", group: "preposition", input: "She is good in mathematics.", expected: "She is good at mathematics."),
        EvaluationCase(id: "grammar-conditional", group: "conditional", input: "If I would know, I would tell you.", expected: "If I knew, I would tell you."),
        EvaluationCase(id: "grammar-modal", group: "modal", input: "You should of called me.", expected: "You should have called me."),
        EvaluationCase(id: "grammar-word-order", group: "word order", input: "I don't know where is he.", expected: "I don't know where he is."),
        EvaluationCase(id: "grammar-repetition", group: "repetition", input: "The result was was incorrect.", expected: "The result was incorrect."),
        EvaluationCase(id: "grammar-spelling", group: "spelling", input: "Teh adress is wrong.", expected: "The address is wrong."),
        EvaluationCase(id: "grammar-capitalization", group: "capitalization", input: "this sentence starts incorrectly.", expected: "This sentence starts incorrectly."),
        EvaluationCase(id: "grammar-question", group: "question punctuation", input: "Can you help me.", expected: "Can you help me?"),
        EvaluationCase(id: "grammar-comma", group: "comma", input: "Let's eat Grandma.", expected: "Let's eat, Grandma."),
        EvaluationCase(id: "grammar-parallelism", group: "parallelism", input: "She likes reading, to swim, and biking.", expected: "She likes reading, swimming, and biking."),
        EvaluationCase(id: "grammar-concision", group: "concision", input: "In order to improve, we revised it.", expected: "To improve, we revised it."),
        EvaluationCase(id: "grammar-plural", group: "plural agreement", input: "They is ready.", expected: "They are ready."),
        EvaluationCase(id: "grammar-third-person", group: "third person", input: "She need more time.", expected: "She needs more time.")
    ]
}
