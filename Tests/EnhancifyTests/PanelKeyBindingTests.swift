import XCTest
@testable import Enhancify

/// The panel's key handling used to replace the user's selection on a bare
/// Return. Replace is destructive and unrecoverable — it overwrites text in
/// whatever app the user came from — so these tests exist mainly to keep that
/// behaviour from coming back.
final class PanelKeyBindingTests: XCTestCase {

    // MARK: - The regression these tests exist for

    func testBareReturnReplacesWhenComposerIsEmptyAndAResultIsReady() {
        let intent = PanelKeyBinding.resolveReturn(
            modifiers: .none,
            canSubmit: false,
            hasAcceptableResult: true
        )
        XCTAssertEqual(intent, .replace, "Return applies the finished result, like ⌘↩.")
    }

    func testBareReturnDoesNothingWithoutAResult() {
        let intent = PanelKeyBinding.resolveReturn(
            modifiers: .none,
            canSubmit: false,
            hasAcceptableResult: false
        )
        XCTAssertEqual(intent, .pass, "Still streaming or nothing to apply.")
    }

    // MARK: - Return

    func testBareReturnSubmitsWhenComposerHasText() {
        let intent = PanelKeyBinding.resolveReturn(
            modifiers: .none,
            canSubmit: true,
            hasAcceptableResult: false
        )
        XCTAssertEqual(intent, .submit)
    }

    func testSubmitWinsOverReplaceOnBareReturn() {
        // Both are possible; the non-destructive one must be chosen.
        let intent = PanelKeyBinding.resolveReturn(
            modifiers: .none,
            canSubmit: true,
            hasAcceptableResult: true
        )
        XCTAssertEqual(intent, .submit)
    }

    // MARK: - Command-Return

    func testCommandReturnReplaces() {
        let intent = PanelKeyBinding.resolveReturn(
            modifiers: .command,
            canSubmit: false,
            hasAcceptableResult: true
        )
        XCTAssertEqual(intent, .replace, "⌘↩ is the explicit, documented replace gesture.")
    }

    func testCommandReturnReplacesEvenWhenComposerHasText() {
        // The explicit modifier beats the implicit submit.
        let intent = PanelKeyBinding.resolveReturn(
            modifiers: .command,
            canSubmit: true,
            hasAcceptableResult: true
        )
        XCTAssertEqual(intent, .replace)
    }

    func testCommandReturnDoesNothingWithoutAResult() {
        let intent = PanelKeyBinding.resolveReturn(
            modifiers: .command,
            canSubmit: false,
            hasAcceptableResult: false
        )
        XCTAssertEqual(intent, .pass, "Nothing to apply, so the key should pass through.")
    }

    // MARK: - Copy

    func testCommandCCopies() {
        let intent = PanelKeyBinding.resolveCharacter("c", modifiers: .command, tabCount: 3)
        XCTAssertEqual(intent, .copy)
    }

    func testBareCIsPassedThroughForTyping() {
        // Otherwise the letter "c" could never be typed into the composer.
        let intent = PanelKeyBinding.resolveCharacter("c", modifiers: .none, tabCount: 3)
        XCTAssertEqual(intent, .pass)
    }

    // MARK: - Tab selection

    func testCommandDigitSelectsTab() {
        XCTAssertEqual(
            PanelKeyBinding.resolveCharacter("1", modifiers: .command, tabCount: 3),
            .selectTab(index: 1)
        )
        XCTAssertEqual(
            PanelKeyBinding.resolveCharacter("3", modifiers: .command, tabCount: 3),
            .selectTab(index: 3)
        )
    }

    func testCommandDigitBeyondTabCountIsIgnored() {
        XCTAssertEqual(
            PanelKeyBinding.resolveCharacter("4", modifiers: .command, tabCount: 3),
            .pass
        )
    }

    func testCommandZeroIsIgnored() {
        // Tabs are 1-based; 0 has no target.
        XCTAssertEqual(
            PanelKeyBinding.resolveCharacter("0", modifiers: .command, tabCount: 3),
            .pass
        )
    }

    func testBareDigitIsPassedThroughForTyping() {
        XCTAssertEqual(
            PanelKeyBinding.resolveCharacter("2", modifiers: .none, tabCount: 3),
            .pass
        )
    }

    func testUnclaimedCharacterPasses() {
        XCTAssertEqual(
            PanelKeyBinding.resolveCharacter("q", modifiers: .command, tabCount: 3),
            .pass
        )
    }

    // MARK: - Escape

    func testEscapeCancels() {
        XCTAssertEqual(PanelKeyBinding.resolveEscape(), .cancel)
    }

    // MARK: - Only Return and ⌘↩ replace

    func testTypedTextIsNeverOverwrittenByBareReturn() {
        // With a refinement typed, Return sends it; it must not paste the
        // current result over the host's text instead.
        for hasResult in [true, false] {
            let intent = PanelKeyBinding.resolveReturn(
                modifiers: .none,
                canSubmit: true,
                hasAcceptableResult: hasResult
            )
            XCTAssertEqual(intent, .submit)
        }
    }

    func testNoUnmodifiedCharacterResolvesToReplace() {
        let characters: [Character] = ["c", "1", "5", "9", "q", "0"]
        for character in characters {
            let intent = PanelKeyBinding.resolveCharacter(character, modifiers: .none, tabCount: 5)
            XCTAssertNotEqual(intent, .replace, "'\(character)' without ⌘ resolved to .replace")
        }
    }

    // MARK: - Tab: Enhance ⇄ Grammar

    private let bothModes: Set<String> = [
        EnhancementAction.enhanceID, EnhancementAction.grammarID
    ]

    func testTabFromEnhanceGoesToGrammar() {
        XCTAssertEqual(
            PanelKeyBinding.resolveTab(currentActionID: EnhancementAction.enhanceID, availableActionIDs: bothModes),
            .switchAction(id: EnhancementAction.grammarID)
        )
    }

    func testTabFromGrammarGoesBackToEnhance() {
        XCTAssertEqual(
            PanelKeyBinding.resolveTab(currentActionID: EnhancementAction.grammarID, availableActionIDs: bothModes),
            .switchAction(id: EnhancementAction.enhanceID)
        )
    }

    func testTabFromAnyOtherTabGoesToEnhance() {
        XCTAssertEqual(
            PanelKeyBinding.resolveTab(currentActionID: "unknown", availableActionIDs: bothModes),
            .switchAction(id: EnhancementAction.enhanceID)
        )
    }

    func testTabPassesWhenTheOtherModeIsNotShown() {
        XCTAssertEqual(
            PanelKeyBinding.resolveTab(
                currentActionID: EnhancementAction.enhanceID,
                availableActionIDs: [EnhancementAction.enhanceID]
            ),
            .pass,
            "Tab must fall through to focus movement when Grammar is not a tab."
        )
    }

    func testCommandLShowsTheComposer() {
        XCTAssertEqual(
            PanelKeyBinding.resolveCharacter("l", modifiers: .command, tabCount: 2),
            .showComposer
        )
        XCTAssertEqual(PanelKeyBinding.resolveCharacter("l", modifiers: .none, tabCount: 2), .pass)
    }
}
