import AppKit
import XCTest
@testable import Enhancify

/// Replace used to paste plain text over a formatted selection: headings
/// became body text, lists lost their bullets, and browser editors joined
/// everything into one line.
final class RichReplacementTests: XCTestCase {
    func testHeadingLevelsFollowSizeRelativeToBody() {
        XCTAssertEqual(RichReplacement.headingRole(fontSize: 28, bodySize: 14), .heading(level: 1))
        XCTAssertEqual(RichReplacement.headingRole(fontSize: 20, bodySize: 14), .heading(level: 2))
        XCTAssertEqual(RichReplacement.headingRole(fontSize: 16, bodySize: 14), .heading(level: 3))
        XCTAssertEqual(RichReplacement.headingRole(fontSize: 14, bodySize: 14), .body)
        XCTAssertEqual(RichReplacement.headingRole(fontSize: nil, bodySize: 14), .body)
    }

    func testMarkersAreStrippedBecauseTheRoleSuppliesThem() {
        XCTAssertEqual(RichReplacement.strippedMarker("- Send the deck."), "Send the deck.")
        XCTAssertEqual(RichReplacement.strippedMarker("2. Book a room."), "Book a room.")
        XCTAssertEqual(RichReplacement.strippedMarker("## Next steps"), "Next steps")
        XCTAssertEqual(RichReplacement.strippedMarker("Plain line"), "Plain line")
        XCTAssertEqual(RichReplacement.strippedMarker("#hashtag stays"), "#hashtag stays")
    }

    func testAppKitListMarkerTextIsKept() {
        XCTAssertEqual(RichReplacement.listMarkerText(of: "\t•\tItem"), "\t•\t")
        XCTAssertEqual(RichReplacement.listMarkerText(of: "\t1.\tItem"), "\t1.\t")
        XCTAssertEqual(RichReplacement.listMarkerText(of: "No marker"), "")
    }

    @MainActor
    func testFormattedSelectionRoundTripsHeadingsAndLists() throws {
        let body = NSFont.systemFont(ofSize: 14)
        let heading = NSFont.boldSystemFont(ofSize: 24)
        let list = NSMutableParagraphStyle()
        list.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        let source = NSMutableAttributedString()
        source.append(NSAttributedString(string: "next steps\n", attributes: [.font: heading]))
        source.append(NSAttributedString(string: "\t•\tsend teh deck\n", attributes: [.font: body, .paragraphStyle: list]))
        source.append(NSAttributedString(string: "\t•\tbook room\n", attributes: [.font: body, .paragraphStyle: list]))
        source.append(NSAttributedString(string: "thanks all", attributes: [.font: body]))
        let rtf = try XCTUnwrap(RichReplacement.rtfData(of: source))

        let payload = try XCTUnwrap(RichReplacement.payload(
            for: "Next steps\n- Send the deck.\n- Book a room.\nThanks, all.",
            source: try XCTUnwrap(RichSelection(rtf: rtf, html: nil))
        ))

        XCTAssertEqual(
            payload.html,
            "<meta charset=\"utf-8\"><h1>Next steps</h1><ul><li>Send the deck.</li><li>Book a room.</li></ul><p>Thanks, all.</p>"
        )
        let rebuilt = try XCTUnwrap(NSAttributedString(rtf: try XCTUnwrap(payload.rtf), documentAttributes: nil))
        XCTAssertTrue(rebuilt.string.hasPrefix("Next steps\n"))
        // Still a real list item in the host, carrying exactly one marker.
        let item = try XCTUnwrap(rebuilt.string.range(of: "Send the deck."))
        let itemStyle = rebuilt.attribute(
            .paragraphStyle,
            at: rebuilt.string.distance(from: rebuilt.string.startIndex, to: item.lowerBound),
            effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertFalse(itemStyle?.textLists.isEmpty ?? true)
        // AppKit may keep the marker as text ("\t•\t") or only as list
        // styling, depending on the OS; the result must match the source.
        let sourceRead = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        XCTAssertEqual(
            rebuilt.string.components(separatedBy: "•").count,
            sourceRead.string.components(separatedBy: "•").count,
            "markers neither dropped nor doubled"
        )
        XCTAssertFalse(rebuilt.string.contains("- Send"))
        let headingFont = try XCTUnwrap(rebuilt.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(headingFont.pointSize, 24)
    }

    @MainActor
    func testResultThatNoLongerLinesUpPastesPlain() throws {
        let source = NSAttributedString(string: "one\ntwo", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let rtf = try XCTUnwrap(RichReplacement.rtfData(of: source))
        XCTAssertNil(RichReplacement.payload(
            for: "One and two.",
            source: try XCTUnwrap(RichSelection(rtf: rtf, html: nil))
        ))
    }

    func testHTMLIsEscaped() {
        XCTAssertEqual(RichReplacement.escaped("a < b & c"), "a &lt; b &amp; c")
    }
}
