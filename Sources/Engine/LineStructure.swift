import Foundation

/// Keeps the author's line structure through a model edit. Models, the small
/// local ones especially, join points written one per line into a single
/// paragraph; Replace then pastes that over a list.
enum LineStructure {
    /// Non-empty lines that start with a list marker (`-`, `*`, `•`, `1.`, `[ ]`).
    static func listItemCount(in text: String) -> Int {
        text.components(separatedBy: .newlines)
            .filter { OutputQuality.listMarkerPrefix(of: $0) != nil }
            .count
    }

    static func nonEmptyLineCount(in text: String) -> Int {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    /// Puts back line breaks the model collapsed into spaces.
    ///
    /// Words are aligned case- and punctuation-insensitively, so "milk" in
    /// the source still finds "milk." in the output, and each source line
    /// break lands after the output word aligned to the source word before
    /// it. Output that already has as many lines as the source is returned
    /// unchanged, as is anything too large to align.
    static func restoringLineBreaks(source: String, output: String) -> String {
        guard nonEmptyLineCount(in: output) < nonEmptyLineCount(in: source) else { return output }
        let sourceWords = words(in: source).words
        let (lead, outputWords) = words(in: output)
        guard sourceWords.count > 1, outputWords.count > 1,
              !WordDiff.exceedsDiffBudget(sourceWords.count, outputWords.count) else { return output }

        let pairs = alignment(sourceWords.map { normalized($0.text) }, outputWords.map { normalized($0.text) })
        var rebuilt = outputWords
        var placed = Set<Int>()
        for index in sourceWords.indices.dropLast() {
            let space = sourceWords[index].space
            guard let first = space.firstIndex(of: "\n"), let last = space.lastIndex(of: "\n") else { continue }
            // The break follows the output word aligned to this source word;
            // an unaligned (misspelt) word borrows the next aligned word and
            // breaks just before it.
            let target: Int
            if let aligned = pairs[index] {
                target = aligned
            } else if let next = (index + 1..<sourceWords.count).first(where: { pairs[$0] != nil }), let aligned = pairs[next] {
                target = aligned - 1
            } else {
                continue
            }
            guard target >= 0, target < rebuilt.count - 1,
                  !rebuilt[target].space.contains("\n"),
                  placed.insert(target).inserted else { continue }
            rebuilt[target].space = String(space[first...last])
        }
        return lead + rebuilt.map { $0.text + $0.space }.joined()
    }

    // MARK: - Alignment

    private struct Word {
        var text: String
        /// Whitespace after the word, newlines included.
        var space: String
    }

    private static func words(in text: String) -> (lead: String, words: [Word]) {
        var lead = ""
        var words: [Word] = []
        for character in text {
            if character.isWhitespace {
                if words.isEmpty { lead.append(character) } else { words[words.count - 1].space.append(character) }
            } else if let last = words.last, last.space.isEmpty {
                words[words.count - 1].text.append(character)
            } else {
                words.append(Word(text: String(character), space: ""))
            }
        }
        return (lead, words)
    }

    /// Lowercased with surrounding punctuation removed. A bare marker (`-`)
    /// normalizes to empty and never aligns, so a dropped marker cannot pull
    /// a break to the wrong word.
    private static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    /// Longest common subsequence of non-empty words: source index → output index.
    private static func alignment(_ a: [String], _ b: [String]) -> [Int: Int] {
        let n = a.count, m = b.count, width = m + 1
        var lengths = [Int32](repeating: 0, count: (n + 1) * width)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lengths[i * width + j] = !a[i].isEmpty && a[i] == b[j]
                    ? lengths[(i + 1) * width + j + 1] + 1
                    : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }
        var pairs: [Int: Int] = [:]
        var i = 0, j = 0
        while i < n, j < m {
            if !a[i].isEmpty, a[i] == b[j] {
                pairs[i] = j
                i += 1
                j += 1
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
