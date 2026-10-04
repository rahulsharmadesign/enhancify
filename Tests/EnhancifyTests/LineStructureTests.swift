import XCTest
@testable import Enhancify

/// Points written one per line must come back one per line. Models join them
/// into a paragraph, and Replace then pastes that over the author's list.
final class LineStructureTests: XCTestCase {
    func testJoinedBulletsAreSplitBackAfterTheMatchingWord() {
        XCTAssertEqual(
            LineStructure.restoringLineBreaks(source: "- buy milk\n- call mom", output: "Buy milk. Call mom."),
            "Buy milk.\nCall mom."
        )
    }

    func testKeptMarkersAreSplitWithoutDoublingThem() {
        XCTAssertEqual(
            LineStructure.restoringLineBreaks(source: "- buy milk\n- call mom", output: "- Buy milk - call mom"),
            "- Buy milk\n- call mom"
        )
    }

    func testNumberedItemsMergedIntoOneParagraph() {
        XCTAssertEqual(
            LineStructure.restoringLineBreaks(
                source: "1. he dont know weather its right\n2. we recieved you're order",
                output: "1. He doesn't know whether it's right. 2. We received your order."
            ),
            "1. He doesn't know whether it's right.\n2. We received your order."
        )
    }

    func testPlainLinesAndBlankLinesComeBack() {
        XCTAssertEqual(
            LineStructure.restoringLineBreaks(
                source: "first point teh end\nsecond point here\n\nthird",
                output: "First point the end. Second point here. Third."
            ),
            "First point the end.\nSecond point here.\n\nThird."
        )
    }

    func testOutputThatKeptItsLinesIsUntouched() {
        XCTAssertEqual(LineStructure.restoringLineBreaks(source: "a\nb", output: "A\nB"), "A\nB")
        XCTAssertEqual(LineStructure.restoringLineBreaks(source: "one line", output: "One line."), "One line.")
    }

    func testListItemCount() {
        XCTAssertEqual(LineStructure.listItemCount(in: "- a\n- b\nplain"), 2)
        XCTAssertEqual(LineStructure.listItemCount(in: "1. a 2. b"), 1)
    }

    // MARK: - Through the output checks

    func testGrammarProofreadRestoresJoinedListItems() {
        let raw = """
        <grammar kind="corrected">Buy milk. Call mom.</grammar>
        <grammar kind="clearer">Buy milk. Call mom.</grammar>
        <grammar kind="tighter">Buy milk. Call mom.</grammar>
        """
        let decision = OutputQuality.evaluate(
            actionID: EnhancementAction.grammarID,
            raw: raw,
            source: "- buy milk\n- call mom",
            canRetry: true
        )
        XCTAssertEqual(decision.outcome, .publish)
        XCTAssertEqual(decision.text, "- Buy milk.\n- Call mom.")
    }

    func testEnhanceThatMergesAListRetriesOnceWithTheListHint() {
        let decision = OutputQuality.evaluate(
            actionID: EnhancementAction.enhanceID,
            raw: "Make the hero text bigger and remove the extra save button.",
            source: "- make hero text bigger\n- remove the extra save button",
            canRetry: true
        )
        XCTAssertEqual(decision.outcome, .retry(previousResult: nil, hint: OutputQuality.listHint))
    }

    func testEnhanceRebuildsTheListWhenTheRetryMergesItAgain() {
        let decision = OutputQuality.evaluate(
            actionID: EnhancementAction.enhanceID,
            raw: "Make the hero text bigger. Remove the extra save button.",
            source: "- make hero text bigger\n- remove the extra save button",
            canRetry: false
        )
        XCTAssertEqual(decision.outcome, .publish)
        XCTAssertEqual(decision.text, "- Make the hero text bigger.\n- Remove the extra save button.")
    }

    func testEnhanceThatKeptTheListPublishesAsIs() {
        let raw = "Make these changes:\n- Make the hero text bigger.\n- Remove the extra save button."
        let decision = OutputQuality.evaluate(
            actionID: EnhancementAction.enhanceID,
            raw: raw,
            source: "- make hero text bigger\n- remove the extra save button",
            canRetry: true
        )
        XCTAssertEqual(decision.outcome, .publish)
        XCTAssertEqual(decision.text, raw)
    }

    func testGrammarStyleIsCheckedForListShapeToo() {
        let decision = OutputQuality.evaluate(
            actionID: EnhancementAction.grammarID,
            raw: "Milk and mom.",
            source: "- buy milk\n- call mom",
            canRetry: true,
            isRewriteStyle: true
        )
        XCTAssertEqual(decision.outcome, .retry(previousResult: nil, hint: OutputQuality.listHint))
    }
}
