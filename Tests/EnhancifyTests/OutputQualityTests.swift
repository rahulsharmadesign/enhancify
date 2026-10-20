import XCTest
@testable import Enhancify

final class OutputQualityTests: XCTestCase {
    private let taggedGrammar = """
    <grammar kind="corrected">There are three things we need to discuss before the meeting tomorrow.</grammar>
    <grammar kind="clearer">There are three things we need to discuss before tomorrow's meeting.</grammar>
    <grammar kind="tighter">There are three things to discuss before tomorrow's meeting.</grammar>
    """

    private func evaluate(
        actionID: String,
        raw: String,
        source: String,
        canRetry: Bool
    ) -> OutputQuality.Decision {
        OutputQuality.evaluate(actionID: actionID, raw: raw, source: source, canRetry: canRetry)
    }

    // MARK: - Grammar

    func testGrammarPublishesTheCorrectedBody() {
        let decision = evaluate(
            actionID: EnhancementAction.grammarID,
            raw: taggedGrammar,
            source: "their are three thing we need to discus before the meting tommorow",
            canRetry: true
        )
        XCTAssertEqual(decision.outcome, .publish)
        XCTAssertEqual(decision.text, "There are three things we need to discuss before the meeting tomorrow.")
    }

    func testGrammarUntaggedRetriesOnce() {
        let decision = evaluate(
            actionID: EnhancementAction.grammarID,
            raw: "He doesn't know whether it's right.",
            source: "he dont know weather its right",
            canRetry: true
        )
        XCTAssertEqual(
            decision.outcome,
            .retry(previousResult: nil, hint: OutputQuality.parseHint)
        )
    }

    func testGrammarParaphraseRetriesThenRevertsCorrectedToSource() {
        let original = "One housekeeping note: your clipboard is empty. My backup of it captured nothing at that moment, so there was nothing to put back."
        let revised = "One housekeeping reminder: your clipboard contains no data. My attempt to back it up found nothing at that time, meaning there was nothing to restore."
        let raw = """
        <grammar kind="corrected">\(revised)</grammar>
        <grammar kind="clearer">\(revised)</grammar>
        <grammar kind="tighter">\(revised)</grammar>
        """
        let retry = evaluate(
            actionID: EnhancementAction.grammarID,
            raw: raw,
            source: original,
            canRetry: true
        )
        XCTAssertEqual(
            retry.outcome,
            .retry(previousResult: revised, hint: nil)
        )
        let reverted = evaluate(
            actionID: EnhancementAction.grammarID,
            raw: raw,
            source: original,
            canRetry: false
        )
        XCTAssertEqual(reverted.outcome, .publish)
        XCTAssertEqual(reverted.text, original)
    }

    func testGrammarCorrectionIsNotTreatedAsParaphrase() {
        let original = "their are three thing we need to discus before the meting tommorow"
        let decision = evaluate(
            actionID: EnhancementAction.grammarID,
            raw: taggedGrammar,
            source: original,
            canRetry: true
        )
        XCTAssertEqual(decision.outcome, .publish)
        XCTAssertTrue(decision.text.contains("There are three things"))
    }

    // MARK: - Grammar list structure

    func testGrammarRestoresDroppedListMarkers() {
        // The reported case: eight selected items came back as bare
        // paragraphs. Markers graft from the source verbatim, so a mid-list
        // selection keeps `6.`, not `1.`.
        let source = """
        6. The avatar/User Profile are not aligned to the left.
        7. Verified check icon should be a solid fill with blue color.
        """
        let raw = """
        <grammar kind="corrected">The avatar/User Profile are not aligned to the left.\nVerified check icon should be a solid fill with blue color.</grammar>
        <grammar kind="clearer">The avatar/User Profile are not aligned to the left.\nThe verified check icon should be a solid fill with blue color.</grammar>
        <grammar kind="tighter">The avatar/User Profile are not aligned left.\nVerified check icon should be solid blue.</grammar>
        """
        let decision = evaluate(
            actionID: EnhancementAction.grammarID,
            raw: raw,
            source: source,
            canRetry: false
        )
        XCTAssertEqual(decision.outcome, .publish)
        XCTAssertEqual(
            decision.text,
            "6. The avatar/User Profile are not aligned to the left.\n7. Verified check icon should be a solid fill with blue color."
        )
    }

    func testListMarkerDetection() {
        XCTAssertEqual(OutputQuality.listMarkerPrefix(of: "6. Aligned left."), "6.")
        XCTAssertEqual(OutputQuality.listMarkerPrefix(of: "  10) Indented."), "10)")
        XCTAssertEqual(OutputQuality.listMarkerPrefix(of: "- Dash item"), "-")
        XCTAssertEqual(OutputQuality.listMarkerPrefix(of: "* Star item"), "*")
        XCTAssertEqual(OutputQuality.listMarkerPrefix(of: "[x] Done task"), "[x]")
        XCTAssertNil(OutputQuality.listMarkerPrefix(of: "Plain sentence."))
        XCTAssertNil(OutputQuality.listMarkerPrefix(of: "All icons which are 20x20 px."))
        XCTAssertNil(OutputQuality.listMarkerPrefix(of: "10% of primary background fill."))
        XCTAssertNil(OutputQuality.listMarkerPrefix(of: "6.No space after marker."))
        XCTAssertNil(OutputQuality.listMarkerPrefix(of: "6.   "))
    }

    func testListMarkerRestoreLeavesNonListsAlone() {
        // Mixed headers and list: not a pure list, untouched.
        XCTAssertEqual(
            OutputQuality.restoringListMarkers(
                source: "Chats\n1. First item.\n2. Second item.",
                body: "Chats\nFirst item.\nSecond item."
            ),
            "Chats\nFirst item.\nSecond item."
        )
        // Model kept its own markers: structure stands.
        XCTAssertEqual(
            OutputQuality.restoringListMarkers(
                source: "1. First.\n2. Second.",
                body: "1. First.\n2. Second."
            ),
            "1. First.\n2. Second."
        )
        // Counts disagree (model merged two items): no graft.
        XCTAssertEqual(
            OutputQuality.restoringListMarkers(
                source: "1. First.\n2. Second.",
                body: "First and second combined."
            ),
            "First and second combined."
        )
        // Bullets graft like numbers.
        XCTAssertEqual(
            OutputQuality.restoringListMarkers(
                source: "- First.\n- Second.",
                body: "First.\nSecond."
            ),
            "- First.\n- Second."
        )
        // Blank-line-separated paragraphs align too.
        XCTAssertEqual(
            OutputQuality.restoringListMarkers(
                source: "1. First.\n2. Second.",
                body: "First.\n\nSecond."
            ),
            "1. First.\n\n2. Second."
        )
    }

    // MARK: - Unchanged

    func testEnhanceEchoRetriesOnceThenPublishes() {
        let source = "write a poem about the sea"
        let retry = evaluate(
            actionID: EnhancementAction.enhanceID,
            raw: source,
            source: source,
            canRetry: true
        )
        XCTAssertEqual(retry.outcome, .retry(previousResult: nil, hint: OutputQuality.echoHint))
        let spent = evaluate(
            actionID: EnhancementAction.enhanceID,
            raw: source,
            source: source,
            canRetry: false
        )
        XCTAssertEqual(spent.outcome, .publish)
        XCTAssertEqual(spent.text, source)
    }

    func testEnhanceThatOnlyFixedCapitalsIsNotAnEcho() {
        let decision = evaluate(
            actionID: EnhancementAction.enhanceID,
            raw: "Write a poem about the sea.",
            source: "write a poem about the sea",
            canRetry: true
        )
        XCTAssertEqual(decision.outcome, .publish)
    }

    func testGrammarUnchangedStillPublishes() {
        let source = "The meeting is at 3 PM tomorrow."
        let raw = """
        <grammar kind="corrected">\(source)</grammar>
        <grammar kind="clearer">\(source)</grammar>
        <grammar kind="tighter">\(source)</grammar>
        """
        let decision = evaluate(
            actionID: EnhancementAction.grammarID,
            raw: raw,
            source: source,
            canRetry: true
        )
        XCTAssertEqual(decision.outcome, .publish)
        XCTAssertEqual(decision.text, source)
    }
}
