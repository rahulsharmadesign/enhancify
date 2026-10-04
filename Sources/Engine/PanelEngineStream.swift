import Foundation
import os

/// One request, fully resolved. `start` decides all of this up front; the
/// stream only reads it.
struct PanelRequest {
    let actionID: String
    let role: ModelRole
    let provider: LLMProvider
    let systemPrompt: String
    let userMessage: String
    let capturedText: String
    /// The refinement typed on this run, carried into a quality retry.
    let instruction: String
    let generation: Int
    /// Grammar's style at `start`. A rewrite style returns one plain document.
    let grammarStyle: GrammarStyle
}

// Running a request: consuming the stream, coalescing publishes, and
// cleaning the output.

extension PanelEngine {
    func runStream(_ request: PanelRequest) {
        let task = Task { [weak self] in
            // Paired with `streamEnded()` in the defer below, so App Nap
            // cannot throttle the stream.
            self?.powerActivity.streamBegan()
            self?.onStreamingStarted?()
            defer {
                self?.powerActivity.streamEnded()
                self?.onStreamingEnded?()
            }
            guard let self else { return }
            var accumulated = ""
            let clock = ContinuousClock()
            let requestStart = clock.now
            var firstTokenAt: ContinuousClock.Instant?
            var lastPublish: ContinuousClock.Instant?
            var reasoningChunks = 0
            do {
                let stream = request.provider.stream(
                    system: request.systemPrompt,
                    user: request.userMessage,
                    role: request.role,
                    actionID: request.actionID
                )
                for try await chunk in stream {
                    guard case .content(let text) = chunk else {
                        // Reasoning must never reach the document. Surface it
                        // as a state so a thinking model doesn't look hung.
                        reasoningChunks += 1
                        if accumulated.isEmpty, reasoningChunks == 1 {
                            self.publish(.thinking, for: request.actionID, generation: request.generation)
                        }
                        continue
                    }
                    // Some models emit leading blank lines (e.g. residue of a
                    // stripped reasoning block); never show or insert them.
                    if accumulated.isEmpty {
                        accumulated = String(text.drop(while: \.isWhitespace))
                    } else {
                        accumulated += text
                    }
                    guard !accumulated.isEmpty else { continue }
                    let now = clock.now
                    if firstTokenAt == nil {
                        firstTokenAt = now
                        engineLogger.notice("ttfb for \(request.actionID): \(Self.milliseconds(now - requestStart)) ms")
                    }
                    // Coalesce: publish the first token immediately, then at
                    // most once per interval. The final text is always
                    // published below, so no content is ever dropped.
                    if let last = lastPublish, now - last < Self.streamPublishInterval {
                        continue
                    }
                    lastPublish = now
                    // Grammar's proofread output is tagged; show it once parsed.
                    if request.actionID == EnhancementAction.grammarID, !request.grammarStyle.isRewrite {
                        continue
                    }
                    self.publish(.streaming(accumulated), for: request.actionID, generation: request.generation)
                }

                // A cancelled byte stream finishes cleanly rather than
                // throwing, so "no content" here means superseded as often as
                // it means the model said nothing. Check before treating it
                // as a failure, or every regenerate flashes a phantom error.
                guard !Task.isCancelled, self.isLive(request.generation, for: request.actionID) else {
                    engineLogger.notice("stream superseded for \(request.actionID)")
                    return
                }
                // Scaffolding last: strippedWrapping matches on prefix and
                // suffix, so removing an opening <context> first would hide the
                // outer wrapping from it.
                var final = Self.strippedScaffolding(
                    Self.strippedWrapping(accumulated.trimmingCharacters(in: .whitespacesAndNewlines)),
                    input: request.capturedText
                )
                let totalMs = Self.milliseconds(clock.now - requestStart)
                engineLogger.notice("stream done for \(request.actionID), length = \(final.count), total = \(totalMs) ms, reasoning chunks discarded = \(reasoningChunks)")
                guard !final.isEmpty else {
                    self.publish(
                        .error("The model returned an empty response — try Regenerate"),
                        for: request.actionID, generation: request.generation
                    )
                    return
                }

                // A rewrite style is one plain document meant to differ from
                // the source: nothing to parse, and the paraphrase ceiling that
                // protects proofreading would reject it on sight. Only its list
                // shape is checked, as for Enhance.
                do {
                    var decision = OutputQuality.evaluate(
                        actionID: request.actionID,
                        raw: final,
                        source: request.capturedText,
                        canRetry: self.canQualityRetry(for: request.actionID),
                        isRewriteStyle: request.grammarStyle.isRewrite
                    )
                    // The parse hint names a tag contract the Apple on-device
                    // prompts deliberately do not have; there a retry is a
                    // plain regenerate.
                    if SettingsStore.shared.activeProvider == .apple,
                       case .retry(let previous, let hint) = decision.outcome, hint == OutputQuality.parseHint {
                        decision.outcome = .retry(previousResult: previous, hint: nil)
                    }
                    switch decision.outcome {
                    case .retry(let previous, let hint):
                        self.markQualityRetry(for: request.actionID)
                        self.publish(.loading, for: request.actionID, generation: request.generation)
                        let actionID = request.actionID
                        let instruction = request.instruction.isEmpty ? nil : request.instruction
                        Task { @MainActor [weak self] in
                            self?.start(
                                actionID: actionID,
                                previousResult: previous,
                                instruction: instruction,
                                retryHint: hint,
                                isQualityRetry: true
                            )
                        }
                        return
                    case .publish:
                        final = decision.text
                    }
                }

                self.publish(.done(final), for: request.actionID, generation: request.generation)
                await self.computeDiff(actionID: request.actionID, original: request.capturedText, revised: final)
            } catch is CancellationError {
                engineLogger.notice("stream cancelled for \(request.actionID)")
            } catch let error as ProviderError {
                if case .cancelled = error { return }
                engineLogger.notice("stream failed for \(request.actionID): \(error.userMessage)")
                self.publish(.error(error.userMessage), for: request.actionID, generation: request.generation)
                self.appState.errorProviders[request.actionID] = SettingsStore.shared.activeProvider
                if error.needsModelSetup {
                    self.appState.errorNeedsModelSetup.insert(request.actionID)
                }
            } catch {
                // localizedDescription only: NSError.userInfo can carry the
                // base URL, which may embed credentials.
                engineLogger.notice("stream failed for \(request.actionID): \(error.localizedDescription)")
                self.publish(.error(error.localizedDescription), for: request.actionID, generation: request.generation)
                self.appState.errorProviders[request.actionID] = SettingsStore.shared.activeProvider
            }
        }
        appState.registerStreamTask(task, for: request.actionID)
    }
}
