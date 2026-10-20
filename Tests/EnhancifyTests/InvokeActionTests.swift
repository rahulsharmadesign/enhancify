import XCTest
@testable import Enhancify

@MainActor
final class InvokeActionTests: XCTestCase {
    private let chrome = HostApp.Info(bundleID: "com.google.Chrome", name: "Google Chrome")
    private let cursor = HostApp.Info(bundleID: "com.anysphere.cursor", name: "Cursor")
    private let slack = HostApp.Info(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    private let mail = HostApp.Info(bundleID: "com.apple.mail", name: "Mail")

    private func landing(
        host: HostApp.Info?,
        hasCapture: Bool = true,
        isEditableField: Bool = false,
        source: String? = "hotkey"
    ) -> String {
        AppCoordinator.initialActionID(
            host: host, hasCapture: hasCapture,
            isEditableField: isEditableField, source: source
        )
    }

    func testEveryInvokeLandsOnOneOfTheTwoTabs() {
        let tabs: Set<String> = [EnhancementAction.enhanceID, EnhancementAction.grammarID]
        for host in [nil, chrome, cursor, slack, mail] {
            for hasCapture in [true, false] {
                for editable in [true, false] {
                    for source in ["hotkey", "clipboard", "dictate", nil] as [String?] {
                        let id = landing(host: host, hasCapture: hasCapture, isEditableField: editable, source: source)
                        XCTAssertTrue(tabs.contains(id), "\(host?.name ?? "nil") → \(id)")
                    }
                }
            }
        }
    }

    func testNoSelectionOpensEnhanceForATypedIdea() {
        XCTAssertEqual(landing(host: chrome, hasCapture: false), EnhancementAction.enhanceID)
        XCTAssertEqual(landing(host: nil, hasCapture: false), EnhancementAction.enhanceID)
    }

    func testSelectionInLLMToolOpensEnhanceEvenInItsEditor() {
        let hosts = [
            cursor,
            HostApp.Info(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
            HostApp.Info(bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
            HostApp.Info(bundleID: "com.openai.chat", name: "ChatGPT")
        ]
        for host in hosts {
            for editable in [true, false] {
                XCTAssertEqual(
                    landing(host: host, isEditableField: editable),
                    EnhancementAction.enhanceID,
                    "\(host.name ?? host.bundleID) editable=\(editable)"
                )
            }
        }
    }

    func testOwnWritingOpensGrammar() {
        XCTAssertEqual(landing(host: chrome, isEditableField: true), EnhancementAction.grammarID)
        XCTAssertEqual(landing(host: slack), EnhancementAction.grammarID, "Electron chat apps hide the field role")
        XCTAssertEqual(landing(host: mail), EnhancementAction.grammarID)
    }

    func testStaticSelectionOpensEnhance() {
        XCTAssertEqual(landing(host: chrome), EnhancementAction.enhanceID)
    }

    /// A Cmd-C fallback capture arrives with a nil source and still routes
    /// as a hotkey, not a clipboard paste.
    func testNilSourceRoutesLikeHotkey() {
        XCTAssertEqual(landing(host: chrome, isEditableField: true, source: nil), EnhancementAction.grammarID)
    }

    func testClipboardOpensEnhance() {
        XCTAssertEqual(landing(host: mail, isEditableField: true, source: "clipboard"), EnhancementAction.enhanceID)
    }

    func testCommunicationPrefixMatchingStaysConservative() {
        XCTAssertTrue(AppCoordinator.isCommunicationApp("com.tinyspeck.slackmacgap"))
        // "chat" must not catch ChatGPT.
        XCTAssertFalse(AppCoordinator.isCommunicationApp("com.openai.chat"))
    }

    func testAIToolsReadTheSelectionWithCommandCFirst() {
        XCTAssertTrue(AppCoordinator.prefersClipboardCapture(host: cursor, isElectronHelper: false))
        XCTAssertTrue(AppCoordinator.prefersClipboardCapture(host: nil, isElectronHelper: true))
        XCTAssertTrue(
            AppCoordinator.prefersClipboardCapture(host: mail, isElectronHelper: false),
            "rich-text apps hand over formatting only on the pasteboard"
        )
        XCTAssertFalse(AppCoordinator.prefersClipboardCapture(host: slack, isElectronHelper: false))
        XCTAssertFalse(AppCoordinator.prefersClipboardCapture(host: nil, isElectronHelper: false))
    }

    func testVSCodeRoutesToEnhance() {
        let vscode = HostApp.Info(bundleID: "com.microsoft.VSCode", name: "Code")
        XCTAssertEqual(landing(host: vscode), EnhancementAction.enhanceID)
        XCTAssertNotNil(TargetProfile.seededID(forBundleID: "com.microsoft.vscode"))
    }
}

/// The outcome strip must survive a Regenerate without unmounting: tearing
/// it down shrinks the chrome, bounces the composer to the middle for a few
/// milliseconds, then regrows everything when the answer lands.
@MainActor
final class ReloadFooterTests: XCTestCase {
    private let actionID = "action-unknown-test"

    private func engine(on state: AppState) -> PanelEngine {
        PanelEngine(appState: state, onDismiss: {})
    }

    func testShowsFooterForDoneOrReloadingOnly() {
        let state = AppState()
        XCTAssertFalse(state.showsFooter(for: actionID))
        state.setResult(.loading, for: actionID)
        XCTAssertFalse(state.showsFooter(for: actionID))
        state.reloadingActions.insert(actionID)
        XCTAssertTrue(state.showsFooter(for: actionID))
        state.setResult(.done("new"), for: actionID)
        XCTAssertTrue(state.showsFooter(for: actionID))
        XCTAssertTrue(state.reloadingActions.isEmpty, "a terminal state clears the reload flag")
    }

    func testErrorAndIdleClearReloadingAndHideTheFooter() {
        for terminal: ResultState in [.error("boom"), .idle] {
            let state = AppState()
            state.reloadingActions.insert(actionID)
            state.setResult(terminal, for: actionID)
            XCTAssertTrue(state.reloadingActions.isEmpty)
            XCTAssertFalse(state.showsFooter(for: actionID))
        }
    }

    func testResetAndDismissClearReloading() {
        let resetState = AppState()
        resetState.reloadingActions.insert(actionID)
        resetState.reset(withCapturedText: "")
        XCTAssertTrue(resetState.reloadingActions.isEmpty)

        let dismissedState = AppState()
        dismissedState.reloadingActions.insert(actionID)
        dismissedState.dismiss()
        XCTAssertTrue(dismissedState.reloadingActions.isEmpty)
    }

    func testRetryWhileStreamingIsANoOp() {
        let state = AppState()
        let engine = engine(on: state)
        state.setResult(.loading, for: actionID)
        engine.retry(actionID: actionID)
        XCTAssertTrue(state.reloadingActions.isEmpty)
        XCTAssertTrue(engine.attempts.isEmpty, "no run may start under the live one")
    }

    func testRetryFromDoneMarksReloadingWithoutStartingUnknownRuns() {
        let state = AppState()
        let engine = engine(on: state)
        state.setResult(.done("old"), for: actionID)
        engine.retry(actionID: actionID)
        XCTAssertEqual(state.reloadingActions, [actionID])
        XCTAssertTrue(engine.attempts.isEmpty, "an unknown action must not start a run")
        XCTAssertTrue(state.showsFooter(for: actionID))
    }

    func testBothTabsGetTheFooter() {
        let state = AppState()
        for id in [EnhancementAction.enhanceID, EnhancementAction.grammarID] {
            state.setResult(.done("old"), for: id)
            XCTAssertTrue(state.showsFooter(for: id), id)
        }
    }
}
