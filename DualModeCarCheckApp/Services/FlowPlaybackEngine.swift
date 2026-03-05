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

    var progressFraction: Double {
        guard totalActions > 0 else { return 0 }
        return Double(currentActionIndex) / Double(totalActions)
    }

    func cancel() {
        cancelled = true
        isPlaying = false
    }

    func playFlow(
        _ flow: RecordedFlow,
        in webView: WKWebView,
        textboxValues: [String: String] = [:],
        onProgress: @escaping (Int, Int) -> Void,
        onComplete: @escaping (Bool) -> Void
    ) async {
        guard !flow.actions.isEmpty else {
            onComplete(false)
            return
        }

        isPlaying = true
        cancelled = false
        totalActions = flow.actions.count
        currentActionIndex = 0

        logger.log("FlowPlayback: starting \(flow.name) — \(flow.actions.count) actions, \(flow.formattedDuration)", category: .automation, level: .info)

        let profile = PPSRStealthService.shared.nextProfile()
        let stealthJS = PPSRStealthService.shared.buildComprehensiveStealthJSPublic(profile: profile)
        _ = try? await webView.evaluateJavaScript(stealthJS)

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

            await executeAction(action, in: webView, textboxValues: textboxValues, sessionId: flow.id)
        }

        currentActionIndex = flow.actions.count
        onProgress(flow.actions.count, flow.actions.count)
        isPlaying = false

        let success = !cancelled
        logger.log("FlowPlayback: \(success ? "completed" : "cancelled") — \(currentActionIndex)/\(totalActions) actions", category: .automation, level: success ? .success : .warning)
        onComplete(success)
    }

    private func executeAction(_ action: RecordedAction, in webView: WKWebView, textboxValues: [String: String], sessionId: String) async {
        switch action.type {
        case .mouseMove:
            guard let pos = action.mousePosition else { return }
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    el.dispatchEvent(new MouseEvent('mousemove', {
                        bubbles: true, cancelable: true,
                        clientX: \(pos.x), clientY: \(pos.y),
                        screenX: \(pos.x), screenY: \(pos.y)
                    }));
                }
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

        case .mouseDown:
            guard let pos = action.mousePosition else { return }
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
                }
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

        case .mouseUp:
            guard let pos = action.mousePosition else { return }
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
                }
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

        case .click:
            guard let pos = action.mousePosition else { return }
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
                }
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

        case .doubleClick:
            guard let pos = action.mousePosition else { return }
            let js = """
            (function(){
                var el = document.elementFromPoint(\(pos.x), \(pos.y));
                if (el) {
                    el.dispatchEvent(new MouseEvent('dblclick', {bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y)}));
                }
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

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
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

        case .keyDown, .keyPress, .keyUp:
            let eventName: String
            switch action.type {
            case .keyDown: eventName = "keydown"
            case .keyPress: eventName = "keypress"
            case .keyUp: eventName = "keyup"
            default: return
            }

            if let label = action.textboxLabel, action.type == .keyDown {
                if let replacementValue = textboxValues[label] {
                    if let key = action.key, key.count == 1 {
                        return
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
                }
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

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
                    }
                })()
                """
                _ = try? await webView.evaluateJavaScript(js)
            }

        case .focus:
            if let sel = action.targetSelector {
                let escaped = sel.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function(){
                    var el = document.querySelector('\(escaped)');
                    if (el) { el.focus(); el.dispatchEvent(new Event('focus',{bubbles:true})); }
                })()
                """
                _ = try? await webView.evaluateJavaScript(js)
            }

        case .blur:
            if let sel = action.targetSelector {
                let escaped = sel.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function(){
                    var el = document.querySelector('\(escaped)');
                    if (el) { el.blur(); el.dispatchEvent(new Event('blur',{bubbles:true})); }
                })()
                """
                _ = try? await webView.evaluateJavaScript(js)
            }

        case .touchStart, .touchEnd, .touchMove:
            guard let pos = action.mousePosition else { return }
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
            default: return
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
                    } catch(e) {
                        el.dispatchEvent(new PointerEvent('\(pointerEventName)',{bubbles:true,cancelable:true,clientX:\(pos.x),clientY:\(pos.y),pointerId:1,pointerType:'touch'}));
                    }
                }
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

        case .textboxEntry:
            if let label = action.textboxLabel, let sel = action.targetSelector {
                let value = textboxValues[label] ?? action.textContent ?? ""
                await typeHumanLike(value, selector: sel, in: webView)
            }

        case .pageLoad, .navigationStart, .pause:
            break
        }
    }

    private func typeHumanLike(_ text: String, selector: String, in webView: WKWebView) async {
        let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
        let focusJS = """
        (function(){
            var el = document.querySelector('\(escaped)');
            if (el) { el.focus(); el.value = ''; el.dispatchEvent(new Event('focus',{bubbles:true})); return 'OK'; }
            return 'NOT_FOUND';
        })()
        """
        _ = try? await webView.evaluateJavaScript(focusJS)

        for char in text {
            let charStr = String(char).replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
            let kc = charKeyCode(char)
            let js = """
            (function(){
                var el = document.activeElement;
                if (!el) return;
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'\(charStr)',keyCode:\(kc),which:\(kc),bubbles:true,cancelable:true}));
                var ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
                var nv = (el.value||'')+'\(charStr)';
                if(ns&&ns.set){ns.set.call(el,nv);}else{el.value=nv;}
                el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:'\(charStr)'}));
                el.dispatchEvent(new KeyboardEvent('keyup',{key:'\(charStr)',keyCode:\(kc),which:\(kc),bubbles:true}));
            })()
            """
            _ = try? await webView.evaluateJavaScript(js)

            let delay = Int.random(in: 35...180)
            try? await Task.sleep(for: .milliseconds(delay))
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
