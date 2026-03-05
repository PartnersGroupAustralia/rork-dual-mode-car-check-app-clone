import Foundation
import WebKit

@MainActor
class FlowPlaybackEngine {
    static let shared = FlowPlaybackEngine()

    private let logger = DebugLogger.shared
    private(set) var isPlaying: Bool = false
    private(set) var currentActionIndex: Int = 0
    private(set) var totalActions: Int = 0
    private var cancelled: Bool = false
    private(set) var lastPlaybackError: String?
    private(set) var failedActionIndices: [Int] = []
    private(set) var healedActionCount: Int = 0

    var progressFraction: Double {
        guard totalActions > 0 else { return 0 }
        return Double(currentActionIndex) / Double(totalActions)
    }

    func cancel() {
        cancelled = true
        isPlaying = false
        logger.log("FlowPlayback: cancelled by user at action \(currentActionIndex)/\(totalActions)", category: .flowRecorder, level: .warning)
    }

    func playFlow(
        _ flow: RecordedFlow,
        in webView: WKWebView,
        textboxValues: [String: String] = [:],
        onProgress: @escaping (Int, Int) -> Void,
        onComplete: @escaping (Bool) -> Void
    ) async {
        guard !flow.actions.isEmpty else {
            logger.log("FlowPlayback: aborted — flow '\(flow.name)' has 0 actions", category: .flowRecorder, level: .error)
            onComplete(false)
            return
        }

        isPlaying = true
        cancelled = false
        totalActions = flow.actions.count
        currentActionIndex = 0
        lastPlaybackError = nil
        failedActionIndices = []
        healedActionCount = 0

        let sessionId = "playback_\(flow.id.prefix(8))"
        logger.startSession(sessionId, category: .flowRecorder, message: "FlowPlayback: starting '\(flow.name)' — \(flow.actions.count) actions, \(flow.formattedDuration)")
        logger.log("FlowPlayback: textbox mappings: \(textboxValues.keys.sorted().joined(separator: ", "))", category: .flowRecorder, level: .debug, sessionId: sessionId)

        let profile = PPSRStealthService.shared.nextProfile()
        let stealthJS = PPSRStealthService.shared.buildComprehensiveStealthJSPublic(profile: profile)
        do {
            _ = try await webView.evaluateJavaScript(stealthJS)
            logger.log("FlowPlayback: stealth JS injected (seed: \(profile.seed))", category: .stealth, level: .debug, sessionId: sessionId)
        } catch {
            logger.logError("FlowPlayback: stealth JS injection failed", error: error, category: .stealth, sessionId: sessionId)
            logger.logHealing(category: .stealth, originalError: error.localizedDescription, healingAction: "Continuing without stealth JS", succeeded: true, sessionId: sessionId)
        }

        for (index, action) in flow.actions.enumerated() {
            if cancelled { break }

            currentActionIndex = index
            onProgress(index, flow.actions.count)

            if action.deltaFromPreviousMs > 0 {
                let delayMs = action.deltaFromPreviousMs
                let jitter = Double.random(in: -0.5...0.5)
                let finalDelay = max(1, delayMs + jitter)
                try? await Task.sleep(for: .milliseconds(Int(finalDelay)))
            }

            if cancelled { break }

            let success = await executeActionWithHealing(action, index: index, in: webView, textboxValues: textboxValues, sessionId: sessionId)
            if !success {
                failedActionIndices.append(index)
                logger.log("FlowPlayback: action #\(index) (\(action.type.rawValue)) failed — continuing", category: .flowRecorder, level: .warning, sessionId: sessionId, metadata: [
                    "actionType": action.type.rawValue,
                    "selector": action.targetSelector ?? "N/A",
                    "position": action.mousePosition.map { "\($0.x),\($0.y)" } ?? "N/A"
                ])
            }
        }

        currentActionIndex = flow.actions.count
        onProgress(flow.actions.count, flow.actions.count)
        isPlaying = false

        let success = !cancelled
        let failRate = failedActionIndices.count
        logger.endSession(sessionId, category: .flowRecorder, message: "FlowPlayback: \(success ? "completed" : "cancelled") — \(currentActionIndex)/\(totalActions) actions, \(failRate) failed, \(healedActionCount) healed", level: success ? (failRate == 0 ? .success : .warning) : .warning)
        onComplete(success)
    }

    private func executeActionWithHealing(_ action: RecordedAction, index: Int, in webView: WKWebView, textboxValues: [String: String], sessionId: String) async -> Bool {
        let startTime = Date()

        let result = await executeAction(action, in: webView, textboxValues: textboxValues, sessionId: sessionId)
        if result { return true }

        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)

        if action.type == .click || action.type == .mouseDown || action.type == .mouseUp {
            if let pos = action.mousePosition {
                logger.log("FlowPlayback: healing click at (\(pos.x),\(pos.y)) — trying alternative dispatch", category: .healing, level: .debug, sessionId: sessionId)
                let healResult = await healClickAction(pos: pos, in: webView)
                if healResult {
                    healedActionCount += 1
                    logger.logHealing(category: .flowRecorder, originalError: "Click dispatch failed at (\(pos.x),\(pos.y))", healingAction: "Alternative click dispatch with focus+click+submit fallback", succeeded: true, attemptNumber: 1, durationMs: elapsed, sessionId: sessionId)
                    return true
                }
            }
        }

        if action.type == .input || action.type == .textboxEntry {
            if let sel = action.targetSelector, let label = action.textboxLabel {
                let value = textboxValues[label] ?? action.textContent ?? ""
                logger.log("FlowPlayback: healing input for '\(label)' — trying fallback selectors", category: .healing, level: .debug, sessionId: sessionId)
                let healResult = await healInputAction(selector: sel, value: value, in: webView)
                if healResult {
                    healedActionCount += 1
                    logger.logHealing(category: .flowRecorder, originalError: "Input fill failed for selector '\(sel)'", healingAction: "Fallback input fill with activeElement and nativeSetter", succeeded: true, attemptNumber: 1, durationMs: elapsed, sessionId: sessionId)
                    return true
                }
            }
        }

        if action.type == .focus {
            if let sel = action.targetSelector {
                let healResult = await healFocusAction(selector: sel, in: webView)
                if healResult {
                    healedActionCount += 1
                    logger.logHealing(category: .flowRecorder, originalError: "Focus failed for '\(sel)'", healingAction: "Tab-based focus fallback", succeeded: true, attemptNumber: 1, durationMs: elapsed, sessionId: sessionId)
                    return true
                }
            }
        }

        logger.logHealing(category: .flowRecorder, originalError: "Action #\(index) (\(action.type.rawValue)) failed", healingAction: "All healing strategies exhausted", succeeded: false, attemptNumber: 1, durationMs: elapsed, sessionId: sessionId)
        return false
    }

    private func healClickAction(pos: RecordedMousePosition, in webView: WKWebView) async -> Bool {
        let js = """
        (function(){
            var el = document.elementFromPoint(\(pos.x), \(pos.y));
            if (!el) return 'NO_ELEMENT';
            try {
                el.focus();
                el.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),pointerId:1,pointerType:'touch'}));
                el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y)}));
                el.dispatchEvent(new PointerEvent('pointerup', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),pointerId:1,pointerType:'touch'}));
                el.dispatchEvent(new MouseEvent('mouseup', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y)}));
                el.dispatchEvent(new MouseEvent('click', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y)}));
                if (typeof el.click === 'function') el.click();
                if (el.tagName === 'A' && el.href) { window.location.href = el.href; }
                if (el.tagName === 'BUTTON' || el.type === 'submit') {
                    var form = el.closest('form');
                    if (form) form.requestSubmit ? form.requestSubmit() : form.submit();
                }
                return 'HEALED';
            } catch(e) { return 'ERROR:' + e.message; }
        })()
        """
        let result = await safeEvalJS(js, in: webView)
        return result == "HEALED"
    }

    private func healInputAction(selector: String, value: String, in webView: WKWebView) async -> Bool {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let selEscaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(){
            var el = document.querySelector('\(selEscaped)');
            if (!el) {
                el = document.activeElement;
                if (!el || el === document.body) {
                    var inputs = document.querySelectorAll('input:not([type=hidden]), textarea');
                    for (var i = 0; i < inputs.length; i++) {
                        if (!inputs[i].value || inputs[i].value.length === 0) { el = inputs[i]; break; }
                    }
                }
            }
            if (!el || el === document.body) return 'NO_ELEMENT';
            try {
                el.focus();
                el.value = '';
                var ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                if (ns && ns.set) { ns.set.call(el, '\(escaped)'); } else { el.value = '\(escaped)'; }
                el.dispatchEvent(new Event('focus', {bubbles:true}));
                el.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data:'\(escaped)'}));
                el.dispatchEvent(new Event('change', {bubbles:true}));
                return el.value === '\(escaped)' ? 'HEALED' : 'VALUE_MISMATCH';
            } catch(e) { return 'ERROR:' + e.message; }
        })()
        """
        let result = await safeEvalJS(js, in: webView)
        return result == "HEALED" || result == "VALUE_MISMATCH"
    }

    private func healFocusAction(selector: String, in webView: WKWebView) async -> Bool {
        let selEscaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(){
            var el = document.querySelector('\(selEscaped)');
            if (!el) {
                var all = document.querySelectorAll('input, textarea, select, button, [tabindex]');
                if (all.length > 0) { el = all[0]; }
            }
            if (!el) return 'NO_ELEMENT';
            try {
                el.focus();
                el.dispatchEvent(new Event('focus', {bubbles:true}));
                el.dispatchEvent(new Event('focusin', {bubbles:true}));
                return 'HEALED';
            } catch(e) { return 'ERROR:' + e.message; }
        })()
        """
        let result = await safeEvalJS(js, in: webView)
        return result == "HEALED"
    }

    private func executeAction(_ action: RecordedAction, in webView: WKWebView, textboxValues: [String: String], sessionId: String) async -> Bool {
        switch action.type {
        case .mouseMove:
            guard let pos = action.mousePosition else { return true }
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    el.dispatchEvent(new MouseEvent('mousemove', {
                        bubbles: true, cancelable: true,
                        clientX: \(pos.x), clientY: \(pos.y),
                        screenX: \(pos.x), screenY: \(pos.y)
                    }));
                    return 'OK';
                }
                return 'NO_ELEMENT';
            })()
            """
            let result = await safeEvalJS(js, in: webView)
            return result != nil

        case .mouseDown:
            guard let pos = action.mousePosition else { return true }
            let btn = action.button ?? 0
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    el.dispatchEvent(new PointerEvent('pointerdown', {
                        bubbles: true, cancelable: true,
                        clientX: \(pos.x), clientY: \(pos.y),
                        pointerId: 1, pointerType: 'mouse', button: \(btn), buttons: 1
                    }));
                    el.dispatchEvent(new MouseEvent('mousedown', {
                        bubbles: true, cancelable: true,
                        clientX: \(pos.x), clientY: \(pos.y),
                        button: \(btn), buttons: 1
                    }));
                    return 'OK';
                }
                return 'NO_ELEMENT';
            })()
            """
            let result = await safeEvalJS(js, in: webView)
            return result == "OK"

        case .mouseUp:
            guard let pos = action.mousePosition else { return true }
            let btn = action.button ?? 0
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    el.dispatchEvent(new PointerEvent('pointerup', {
                        bubbles: true, cancelable: true,
                        clientX: \(pos.x), clientY: \(pos.y),
                        pointerId: 1, pointerType: 'mouse', button: \(btn)
                    }));
                    el.dispatchEvent(new MouseEvent('mouseup', {
                        bubbles: true, cancelable: true,
                        clientX: \(pos.x), clientY: \(pos.y),
                        button: \(btn)
                    }));
                    return 'OK';
                }
                return 'NO_ELEMENT';
            })()
            """
            let result = await safeEvalJS(js, in: webView)
            return result == "OK"

        case .click:
            guard let pos = action.mousePosition else { return true }
            let btn = action.button ?? 0
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    el.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),pointerId:1,pointerType:'mouse',button:\(btn),buttons:1}));
                    el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),button:\(btn),buttons:1}));
                    el.dispatchEvent(new PointerEvent('pointerup', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),pointerId:1,pointerType:'mouse',button:\(btn)}));
                    el.dispatchEvent(new MouseEvent('mouseup', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),button:\(btn)}));
                    el.dispatchEvent(new MouseEvent('click', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),button:\(btn)}));
                    if (typeof el.click === 'function') el.click();
                    return 'OK';
                }
                return 'NO_ELEMENT';
            })()
            """
            let result = await safeEvalJS(js, in: webView)
            return result == "OK"

        case .doubleClick:
            guard let pos = action.mousePosition else { return true }
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    el.dispatchEvent(new MouseEvent('dblclick', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y)}));
                    return 'OK';
                }
                return 'NO_ELEMENT';
            })()
            """
            let result = await safeEvalJS(js, in: webView)
            return result == "OK"

        case .scroll:
            let dx = action.scrollDeltaX ?? 0
            let dy = action.scrollDeltaY ?? 0
            let js = """
            (function(){
                window.scrollBy({ left: \(dx), top: \(dy), behavior: 'auto' });
                document.dispatchEvent(new WheelEvent('wheel', {
                    bubbles: true, cancelable: true,
                    deltaX: \(dx), deltaY: \(dy), deltaMode: 0
                }));
                return 'OK';
            })()
            """
            _ = await safeEvalJS(js, in: webView)
            return true

        case .keyDown, .keyPress, .keyUp:
            let eventName: String
            switch action.type {
            case .keyDown: eventName = "keydown"
            case .keyPress: eventName = "keypress"
            case .keyUp: eventName = "keyup"
            default: return true
            }

            if let label = action.textboxLabel, action.type == .keyDown {
                if let _ = textboxValues[label] {
                    if let key = action.key, key.count == 1 {
                        return true
                    }
                }
            }

            let key = (action.key ?? "").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
            let code = (action.code ?? "").replacingOccurrences(of: "'", with: "\\'")
            let kc = action.keyCode ?? 0
            let shift = action.shiftKey ?? false
            let ctrl = action.ctrlKey ?? false
            let alt = action.altKey ?? false
            let meta = action.metaKey ?? false

            let targetJS: String
            if let sel = action.targetSelector {
                let escaped = sel.replacingOccurrences(of: "'", with: "\\'")
                targetJS = "document.querySelector('\(escaped)') || document.activeElement || document.body"
            } else {
                targetJS = "document.activeElement || document.body"
            }

            let js = """
            (function(){
                var el = \(targetJS);
                if (el) {
                    el.dispatchEvent(new KeyboardEvent('\(eventName)', {
                        key: '\(key)', code: '\(code)',
                        keyCode: \(kc), which: \(kc), charCode: \(action.charCode ?? 0),
                        bubbles: true, cancelable: true,
                        shiftKey: \(shift), ctrlKey: \(ctrl), altKey: \(alt), metaKey: \(meta)
                    }));
                    return 'OK';
                }
                return 'NO_ELEMENT';
            })()
            """
            _ = await safeEvalJS(js, in: webView)
            return true

        case .input:
            if let label = action.textboxLabel, let sel = action.targetSelector {
                let value: String
                if let replacement = textboxValues[label] {
                    value = replacement
                } else {
                    value = action.textContent ?? ""
                }
                let escaped = value.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
                let selEscaped = sel.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function(){
                    var el = document.querySelector('\(selEscaped)') || document.activeElement;
                    if (el) {
                        var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                        if (nativeSetter && nativeSetter.set) { nativeSetter.set.call(el, '\(escaped)'); }
                        else { el.value = '\(escaped)'; }
                        el.dispatchEvent(new InputEvent('input', {bubbles:true,inputType:'insertText',data:'\(escaped)'}));
                        el.dispatchEvent(new Event('change', {bubbles:true}));
                        return el.value === '\(escaped)' ? 'OK' : 'VALUE_MISMATCH';
                    }
                    return 'NO_ELEMENT';
                })()
                """
                let result = await safeEvalJS(js, in: webView)
                return result == "OK" || result == "VALUE_MISMATCH"
            }
            return true

        case .focus:
            if let sel = action.targetSelector {
                let escaped = sel.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function(){
                    var el = document.querySelector('\(escaped)');
                    if (el) { el.focus(); el.dispatchEvent(new Event('focus',{bubbles:true})); return 'OK'; }
                    return 'NO_ELEMENT';
                })()
                """
                let result = await safeEvalJS(js, in: webView)
                return result == "OK"
            }
            return true

        case .blur:
            if let sel = action.targetSelector {
                let escaped = sel.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function(){
                    var el = document.querySelector('\(escaped)');
                    if (el) { el.blur(); el.dispatchEvent(new Event('blur',{bubbles:true})); return 'OK'; }
                    return 'NO_ELEMENT';
                })()
                """
                _ = await safeEvalJS(js, in: webView)
            }
            return true

        case .touchStart, .touchEnd, .touchMove:
            guard let pos = action.mousePosition else { return true }
            let touchEventName: String
            let pointerEventName: String
            switch action.type {
            case .touchStart:
                touchEventName = "touchstart"
                pointerEventName = "pointerdown"
            case .touchEnd:
                touchEventName = "touchend"
                pointerEventName = "pointerup"
            case .touchMove:
                touchEventName = "touchmove"
                pointerEventName = "pointermove"
            default: return true
            }
            let isTouchEnd = action.type == .touchEnd ? "true" : "false"
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    try {
                        var t = new Touch({identifier:Date.now(),target:el,clientX:\(pos.x),clientY:\(pos.y),pageX:\(pos.viewportX),pageY:\(pos.viewportY)});
                        var touches = \(isTouchEnd) ? [] : [t];
                        el.dispatchEvent(new TouchEvent('\(touchEventName)',{bubbles:true,cancelable:true,touches:touches,targetTouches:touches,changedTouches:[t]}));
                        return 'OK';
                    } catch(e) {
                        el.dispatchEvent(new PointerEvent('\(pointerEventName)',{bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),pointerId:1,pointerType:'touch'}));
                        return 'FALLBACK';
                    }
                }
                return 'NO_ELEMENT';
            })()
            """
            _ = await safeEvalJS(js, in: webView)
            return true

        case .textboxEntry:
            if let label = action.textboxLabel, let sel = action.targetSelector {
                let value = textboxValues[label] ?? action.textContent ?? ""
                let typeResult = await typeHumanLike(value, selector: sel, in: webView, sessionId: sessionId)
                return typeResult
            }
            return true

        case .pageLoad, .navigationStart, .pause:
            return true
        }
    }

    private func typeHumanLike(_ text: String, selector: String, in webView: WKWebView, sessionId: String) async -> Bool {
        let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
        let focusJS = """
        (function(){
            var el = document.querySelector('\(escaped)');
            if (el) { el.focus(); el.value = ''; el.dispatchEvent(new Event('focus',{bubbles:true})); return 'OK'; }
            return 'NOT_FOUND';
        })()
        """
        let focusResult = await safeEvalJS(focusJS, in: webView)
        if focusResult == "NOT_FOUND" {
            logger.log("FlowPlayback: typeHumanLike — selector '\(selector)' not found", category: .flowRecorder, level: .warning, sessionId: sessionId)
            return false
        }

        for char in text {
            let charStr = String(char).replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
            let kc = charKeyCode(char)
            let js = """
            (function(){
                var el = document.activeElement;
                if (!el) return 'NO_ACTIVE';
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'\(charStr)',keyCode:\(kc),which:\(kc),bubbles:true,cancelable:true}));
                var ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
                var nv = (el.value||'')+'\(charStr)';
                if(ns&&ns.set){ns.set.call(el,nv);}else{el.value=nv;}
                el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:'\(charStr)'}));
                el.dispatchEvent(new KeyboardEvent('keyup',{key:'\(charStr)',keyCode:\(kc),which:\(kc),bubbles:true}));
                return 'OK';
            })()
            """
            _ = await safeEvalJS(js, in: webView)

            let delay = Int.random(in: 35...180)
            try? await Task.sleep(for: .milliseconds(delay))
        }
        return true
    }

    private func safeEvalJS(_ js: String, in webView: WKWebView) async -> String? {
        do {
            let result = try await webView.evaluateJavaScript(js)
            if let str = result as? String { return str }
            if let num = result as? NSNumber { return "\(num)" }
            return nil
        } catch {
            logger.logError("FlowPlayback: JS evaluation failed", error: error, category: .webView, metadata: [
                "jsPrefix": String(js.prefix(80))
            ])
            return nil
        }
    }

    private func charKeyCode(_ char: Character) -> Int {
        let s = String(char).uppercased()
        guard let ascii = s.unicodeScalars.first?.value else { return 0 }
        if ascii >= 65 && ascii <= 90 { return Int(ascii) }
        if ascii >= 48 && ascii <= 57 { return Int(ascii) }
        switch char {
        case "@": return 50
        case ".": return 190
        case "-": return 189
        case "_": return 189
        default: return Int(ascii)
        }
    }
}
