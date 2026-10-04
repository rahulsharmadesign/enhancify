import Foundation

/// Post-stream checks. Prompts are a probability; Replace pastes into a real
/// document, so Grammar's tag contract, Grammar-vs-paraphrase, and the
/// author's list structure are enforced here.
enum OutputQuality {
    /// Matches `PanelEngine.grammarParaphraseCeiling`. Corrections cluster
    /// near 0; the reported synonym-swap scored 1.0. 0.4 sits in the gap.
    static let grammarParaphraseCeiling = 0.4

    static let parseHint = """
    Your previous output did not use the required tags. Output ONLY the tagged documents in the exact format specified in the system instructions, and nothing else.
    """

    static let listHint = """
    Your previous output merged the author's points into running text. The source is written as a list: keep it as a list, one point per line, with the same markers (`-`, `*`, `1.`), order, and number of points. Improve and correct the words inside each point only.
    """

    enum Outcome: Equatable {
        case publish
        case retry(previousResult: String?, hint: String?)
    }

    struct Decision: Equatable {
        var outcome: Outcome
        /// What publishes: Grammar's Corrected text, or the raw output.
        var text: String
    }

    /// Proofread Grammar gets the full check. Enhance and the Grammar
    /// rewrite styles change wording on purpose, so only their list shape is
    /// checked.
    static func evaluate(
        actionID: String,
        raw: String,
        source: String,
        canRetry: Bool,
        isRewriteStyle: Bool = false
    ) -> Decision {
        if actionID == EnhancementAction.grammarID, !isRewriteStyle {
            return evaluateGrammar(raw: raw, source: source, canRetry: canRetry)
        }
        return evaluateListShape(raw: raw, source: source, canRetry: canRetry)
    }

    // MARK: - List shape

    /// A source written as points must come back as points. One retry with
    /// `listHint`; if the model merges them again, rebuild the lines from the
    /// source, keeping the repair only when every point came back.
    private static func evaluateListShape(raw: String, source: String, canRetry: Bool) -> Decision {
        let wanted = LineStructure.listItemCount(in: source)
        guard wanted >= 2, LineStructure.listItemCount(in: raw) < 2 else {
            return Decision(outcome: .publish, text: raw)
        }
        if canRetry {
            return Decision(outcome: .retry(previousResult: nil, hint: listHint), text: raw)
        }
        let repaired = restoringListMarkers(
            source: source,
            body: LineStructure.restoringLineBreaks(source: source, output: raw)
        )
        return Decision(outcome: .publish, text: LineStructure.listItemCount(in: repaired) >= wanted ? repaired : raw)
    }

    // MARK: - Grammar

    private static func evaluateGrammar(raw: String, source: String, canRetry: Bool) -> Decision {
        let parsed = GrammarSuggestions.parseWithStatus(raw)
        // Small models sometimes return list items as bare paragraphs with
        // every marker dropped. Markers are known strings from the source, so
        // they graft back exactly; anything that does not align 1:1 is left
        // alone. Runs before paraphrase scoring so the score sees the text
        // that will actually publish.
        // Joined lines are split back first, so the marker graft below sees
        // one line per source item.
        let corrected = (GrammarSuggestions.body(in: parsed.suggestions, matching: .corrected)
            ?? parsed.suggestions.first?.body)
            .map {
                restoringListMarkers(
                    source: source,
                    body: LineStructure.restoringLineBreaks(source: source, output: $0)
                )
            }
        if parsed.usedFallback, canRetry, corrected != nil {
            return Decision(outcome: .retry(previousResult: nil, hint: parseHint), text: raw)
        }
        guard let corrected else { return Decision(outcome: .publish, text: raw) }

        let sourceTrimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceTrimmed.isEmpty {
            let score = WordDiff.paraphraseScore(WordDiff.diff(original: source, revised: corrected))
            if score > grammarParaphraseCeiling {
                // Rewrote rather than corrected. One retry, then fall back to
                // the author's own text rather than publish a paraphrase.
                if canRetry {
                    return Decision(outcome: .retry(previousResult: corrected, hint: nil), text: raw)
                }
                return Decision(outcome: .publish, text: source)
            }
        }
        return Decision(outcome: .publish, text: corrected)
    }

    // MARK: - Grammar list structure

    /// Leading marker of one list item line (`1.` `2)` `-` `*` `•` `[ ]`
    /// `[x]`), or nil when the line is not a list item. A marker needs
    /// trailing whitespace and real text after it, so `20x20 px`, `10% of`,
    /// and `[UIKit]` never read as markers.
    static func listMarkerPrefix(of line: String) -> String? {
        var rest = line[line.startIndex...]
        while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
            return String(rest.prefix(3))
        }
        if let first = rest.first, "-*•‣".contains(first) {
            let after = rest.dropFirst()
            guard after.first?.isWhitespace == true,
                  after.dropFirst().contains(where: { !$0.isWhitespace })
            else { return nil }
            return String(first)
        }
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        var tail = rest.dropFirst(digits.count)
        guard tail.first == "." || tail.first == ")" else { return nil }
        let punct = tail.first!
        tail = tail.dropFirst()
        guard tail.first?.isWhitespace == true,
              tail.dropFirst().contains(where: { !$0.isWhitespace })
        else { return nil }
        return String(digits) + String(punct)
    }

    /// Puts back list markers the model dropped. Only when every non-empty
    /// source line carries a marker, the body holds the same number of
    /// markerless paragraphs, and none of them kept a marker: then each
    /// paragraph is the corrected item with its marker missing, and the
    /// source markers go back on verbatim — a mid-list selection keeps `6.`,
    /// not `1.`. Anything else returns the body untouched.
    static func restoringListMarkers(source: String, body: String) -> String {
        let sourceLines = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !sourceLines.isEmpty else { return body }
        var markers: [String] = []
        for line in sourceLines {
            guard let marker = listMarkerPrefix(of: line) else { return body }
            markers.append(marker)
        }
        // Blank-line blocks first (the shape Grammar emits), else one item
        // per non-empty line.
        let blocks = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let lines = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let units: [String]
        let joiner: String
        if blocks.count == markers.count {
            units = blocks
            joiner = "\n\n"
        } else if lines.count == markers.count {
            units = lines
            joiner = "\n"
        } else {
            return body
        }
        // Never double-mark: if the model kept any marker, its structure stands.
        guard !units.contains(where: { listMarkerPrefix(of: $0) != nil }) else { return body }
        return zip(markers, units).map { "\($0) \($1)" }.joined(separator: joiner)
    }
}
