import AppKit

/// The formatting of a captured selection, as the host put it on the
/// pasteboard. Raw data so it can cross from capture to the panel freely; it
/// is decoded only at Replace time, on the main actor.
struct RichSelection: Sendable, Equatable {
    var rtf: Data?
    var html: Data?

    init?(rtf: Data?, html: Data?) {
        guard rtf != nil || html != nil else { return nil }
        self.rtf = rtf
        self.html = html
    }

    init?(pasteboard: NSPasteboard) {
        self.init(rtf: pasteboard.data(forType: .rtf), html: pasteboard.data(forType: .html))
    }
}

/// One paragraph's place in the document: what Replace has to give back.
enum ParagraphRole: Equatable {
    case body
    case heading(level: Int)
    case bullet
    case numbered
}

/// Rebuilds a plain result with the source selection's structure.
///
/// The model sees and returns plain text, so headings, list styling, and
/// paragraph formatting were lost on Replace: everything landed as body text
/// and, in browser editors, often as one line. When the result keeps one
/// line per source paragraph, each line takes its source paragraph back:
/// RTF (exact fonts and paragraph styles) for native rich-text apps, and
/// semantic HTML (h1–h3, lists, bold) for web and Electron editors, which
/// apply their own styles to it. Anything that does not pair up pastes as
/// plain text, unchanged.
enum RichReplacement {
    struct Payload {
        var rtf: Data?
        var html: String
    }

    @MainActor
    static func payload(for result: String, source: RichSelection) -> Payload? {
        // RTF carries the host's own fonts; HTML imported by AppKit does not
        // (unknown web fonts fall back to Times), so only RTF is re-emitted
        // as RTF.
        let fromRTF = source.rtf.flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
        let fromHTML = fromRTF == nil
            ? source.html.flatMap { try? NSAttributedString(data: $0, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) }
            : nil
        guard let document = fromRTF ?? fromHTML else { return nil }
        let paragraphs = sourceParagraphs(of: document)
        guard let lines = pairedLines(result: result, paragraphs: paragraphs) else { return nil }
        let rtf = fromRTF != nil ? attributedResult(lines: lines).flatMap(rtfData(of:)) : nil
        return Payload(rtf: rtf, html: html(lines: lines))
    }

    // MARK: - Source

    struct SourceParagraph {
        var text: String
        var attributes: [NSAttributedString.Key: Any]
        var role: ParagraphRole
        var isBold: Bool
    }

    static func sourceParagraphs(of document: NSAttributedString) -> [SourceParagraph] {
        let string = document.string as NSString
        var raw: [(String, [NSAttributedString.Key: Any])] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { text, range, _, _ in
            let text = text ?? ""
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty, document.length > 0 else { return }
            let location = min(range.location, document.length - 1)
            raw.append((text, document.attributes(at: location, effectiveRange: nil)))
        }
        let body = bodyFontSize(raw.map(\.1))
        return raw.map { text, attributes in
            let font = attributes[.font] as? NSFont
            let bold = font.map { $0.fontDescriptor.symbolicTraits.contains(.bold) } ?? false
            return SourceParagraph(
                text: text,
                attributes: attributes,
                role: role(of: attributes, fontSize: font?.pointSize, bodySize: body),
                isBold: bold
            )
        }
    }

    /// The most common font size: the body text everything else is measured against.
    static func bodyFontSize(_ attributes: [[NSAttributedString.Key: Any]]) -> CGFloat? {
        var counts: [CGFloat: Int] = [:]
        for item in attributes {
            if let size = (item[.font] as? NSFont)?.pointSize { counts[size, default: 0] += 1 }
        }
        return counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    static func role(of attributes: [NSAttributedString.Key: Any], fontSize: CGFloat?, bodySize: CGFloat?) -> ParagraphRole {
        if let lists = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists, let list = lists.last {
            return list.isOrdered ? .numbered : .bullet
        }
        return headingRole(fontSize: fontSize, bodySize: bodySize)
    }

    /// Pure size rule, so it is testable without fonts.
    static func headingRole(fontSize: CGFloat?, bodySize: CGFloat?) -> ParagraphRole {
        guard let fontSize, let bodySize, bodySize > 0 else { return .body }
        let ratio = fontSize / bodySize
        if ratio >= 1.6 { return .heading(level: 1) }
        if ratio >= 1.3 { return .heading(level: 2) }
        if ratio >= 1.12 { return .heading(level: 3) }
        return .body
    }

    // MARK: - Pairing

    struct Line {
        /// Result text with any list marker removed; the role supplies it.
        var text: String
        var source: SourceParagraph?
    }

    /// One result line per source paragraph, or nil when they do not line up.
    /// Blank result lines are kept as spacing and pair with nothing.
    static func pairedLines(result: String, paragraphs: [SourceParagraph]) -> [Line]? {
        let resultLines = result.components(separatedBy: .newlines)
        let filled = resultLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !paragraphs.isEmpty, filled.count == paragraphs.count else { return nil }
        var index = 0
        return resultLines.map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return Line(text: "", source: nil) }
            defer { index += 1 }
            let source = paragraphs[index]
            let text = source.role == .body ? line : strippedMarker(line)
            return Line(text: text, source: source)
        }
    }

    /// "- item", "1. item", "• item", "## Title" → the words alone.
    static func strippedMarker(_ line: String) -> String {
        var rest = Substring(line).drop(while: \.isWhitespace)
        if let marker = OutputQuality.listMarkerPrefix(of: String(rest)) {
            rest = rest.dropFirst(marker.count).drop(while: \.isWhitespace)
        } else if rest.hasPrefix("#") {
            let hashes = rest.prefix(while: { $0 == "#" })
            if hashes.count <= 6, rest.dropFirst(hashes.count).first == " " {
                rest = rest.dropFirst(hashes.count).drop(while: \.isWhitespace)
            }
        }
        return String(rest)
    }

    // MARK: - Output

    /// Each line with its source paragraph's attributes. List lines get the
    /// source's marker text back, since AppKit keeps markers in the string.
    static func attributedResult(lines: [Line]) -> NSAttributedString? {
        let output = NSMutableAttributedString()
        var previous: [NSAttributedString.Key: Any] = [:]
        for (offset, line) in lines.enumerated() {
            let newline = offset == lines.count - 1 ? "" : "\n"
            guard let source = line.source else {
                output.append(NSAttributedString(string: newline, attributes: previous))
                continue
            }
            var text = line.text
            if source.role == .bullet || source.role == .numbered {
                text = listMarkerText(of: source.text) + text
            }
            previous = source.attributes
            output.append(NSAttributedString(string: text + newline, attributes: source.attributes))
        }
        return output.length > 0 ? output : nil
    }

    /// AppKit stores a list item as "\t•\tText" or "\t1.\tText".
    static func listMarkerText(of paragraph: String) -> String {
        guard let match = paragraph.range(of: #"^\t?[^\t]{1,8}\t"#, options: .regularExpression) else { return "" }
        return String(paragraph[match])
    }

    static func rtfData(of string: NSAttributedString) -> Data? {
        try? string.data(
            from: NSRange(location: 0, length: string.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Semantic HTML only — no fonts or sizes — so the editor's own styles
    /// render the headings, lists, and paragraphs.
    static func html(lines: [Line]) -> String {
        var parts: [String] = []
        var openList: String?
        func closeList() {
            if let tag = openList { parts.append("</\(tag)>") }
            openList = nil
        }
        for line in lines {
            guard let source = line.source else {
                closeList()
                continue
            }
            var inner = escaped(line.text)
            if source.isBold, source.role == .body { inner = "<b>\(inner)</b>" }
            switch source.role {
            case .bullet, .numbered:
                let tag = source.role == .bullet ? "ul" : "ol"
                if openList != tag {
                    closeList()
                    parts.append("<\(tag)>")
                    openList = tag
                }
                parts.append("<li>\(inner)</li>")
            case .heading(let level):
                closeList()
                parts.append("<h\(level)>\(inner)</h\(level)>")
            case .body:
                closeList()
                parts.append("<p>\(inner)</p>")
            }
        }
        closeList()
        return "<meta charset=\"utf-8\">" + parts.joined()
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
