import Foundation
import Observation
import WebKit

@Observable
class FlowRecorderViewModel {
    var targetURL: String = "https://joefortune24.com/login"
    var flowName: String = ""
    var isRecording: Bool = false
    var isPlaying: Bool = false
    var savedFlows: [RecordedFlow] = []
    var currentActions: [RecordedAction] = []
    var recordingDurationMs: Double = 0
    var playbackProgress: Double = 0
    var playbackActionIndex: Int = 0
    var playbackTotalActions: Int = 0
    var showSaveSheet: Bool = false
    var showPlaybackSheet: Bool = false
    var selectedFlow: RecordedFlow?
    var textboxValues: [String: String] = [:]
    var statusMessage: String = ""
    var fingerprintScore: String = "—"
    var pageTitle: String = ""
    var showExportSheet: Bool = false
    var showImportPicker: Bool = false
    var lastError: String?
    var failedActions: Int = 0
    var healedActions: Int = 0

    private let persistence = FlowPersistenceService.shared
    private let playbackEngine = FlowPlaybackEngine.shared
    private let logger = DebugLogger.shared
    private var recordingStartTime: Double = 0
    private var durationTimer: Timer?
    weak var activeWebView: WKWebView?

    var currentActionCount: Int { currentActions.count }

    var mouseMovements: Int { currentActions.filter { $0.type == .mouseMove }.count }
    var clicks: Int { currentActions.filter { $0.type == .click || $0.type == .mouseDown }.count }
    var keystrokes: Int { currentActions.filter { $0.type == .keyDown }.count }
    var scrollEvents: Int { currentActions.filter { $0.type == .scroll }.count }

    var detectedTextboxes: [String] {
        let labels = Set(currentActions.compactMap(\.textboxLabel))
        return labels.sorted()
    }

    init() {
        logger.log("FlowRecorderViewModel: initializing, loading saved flows", category: .flowRecorder, level: .debug)
        savedFlows = persistence.loadFlows()
        logger.log("FlowRecorderViewModel: loaded \(savedFlows.count) saved flows", category: .flowRecorder, level: .info)
    }

    func startRecording() {
        guard !isRecording else {
            logger.log("FlowRecorder: startRecording called while already recording — ignored", category: .flowRecorder, level: .warning)
            return
        }
        currentActions = []
        recordingDurationMs = 0
        recordingStartTime = ProcessInfo.processInfo.systemUptime * 1000
        isRecording = true
        lastError = nil
        statusMessage = "Recording..."

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.recordingDurationMs = ProcessInfo.processInfo.systemUptime * 1000 - self.recordingStartTime
            }
        }

        logger.startSession("recording", category: .flowRecorder, message: "FlowRecorder: recording started for \(targetURL)")
    }

    func stopRecording() {
        guard isRecording else {
            logger.log("FlowRecorder: stopRecording called while not recording — ignored", category: .flowRecorder, level: .warning)
            return
        }
        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil
        statusMessage = "Recording stopped — \(currentActions.count) actions captured"

        logger.endSession("recording", category: .flowRecorder, message: "FlowRecorder: recording stopped — \(currentActions.count) actions, \(String(format: "%.1f", recordingDurationMs / 1000))s", level: currentActions.isEmpty ? .warning : .success)

        if currentActions.isEmpty {
            logger.log("FlowRecorder: recording produced 0 actions — possible JS injection failure", category: .flowRecorder, level: .error, metadata: [
                "url": targetURL,
                "duration": String(format: "%.1f", recordingDurationMs / 1000)
            ])
            lastError = "No actions recorded. The page may be blocking the recorder script."
        } else {
            logger.log("FlowRecorder: breakdown — mouse:\(mouseMovements) clicks:\(clicks) keys:\(keystrokes) scrolls:\(scrollEvents) textboxes:\(detectedTextboxes.count)", category: .flowRecorder, level: .info)
            showSaveSheet = true
        }
    }

    func appendActions(_ actions: [RecordedAction]) {
        guard !actions.isEmpty else { return }
        currentActions.append(contentsOf: actions)
        logger.log("FlowRecorder: received \(actions.count) actions (total: \(currentActions.count))", category: .flowRecorder, level: .trace)
    }

    func handlePageLoaded(_ title: String) {
        pageTitle = title
        logger.log("FlowRecorder: page loaded — \(title)", category: .webView, level: .info, metadata: ["url": targetURL])
        validateFingerprint()
    }

    func handlePageLoadFailed(_ error: String) {
        lastError = error
        logger.log("FlowRecorder: page load FAILED — \(error)", category: .webView, level: .error, metadata: ["url": targetURL])
        statusMessage = "Page load failed: \(error)"
    }

    func saveCurrentFlow() {
        let name = flowName.isEmpty ? "Flow \(savedFlows.count + 1)" : flowName
        let textboxMappings = detectedTextboxes.enumerated().map { index, label in
            let lastInput = currentActions.last(where: { $0.textboxLabel == label && $0.type == .input })
            let selector = lastInput?.targetSelector ?? ""
            let originalText = lastInput?.textContent ?? ""
            return RecordedFlow.TextboxMapping(
                label: label,
                selector: selector,
                originalText: originalText,
                placeholderKey: label
            )
        }

        let flow = RecordedFlow(
            name: name,
            url: targetURL,
            actions: currentActions,
            textboxMappings: textboxMappings,
            totalDurationMs: recordingDurationMs,
            actionCount: currentActions.count
        )

        savedFlows.insert(flow, at: 0)
        persistence.saveFlows(savedFlows)
        flowName = ""
        showSaveSheet = false
        statusMessage = "Flow '\(name)' saved — \(flow.actionCount) actions"
        logger.log("FlowRecorder: saved flow '\(name)' — \(flow.actionCount) actions, \(textboxMappings.count) textbox mappings", category: .persistence, level: .success, metadata: [
            "actionCount": "\(flow.actionCount)",
            "textboxes": textboxMappings.map(\.label).joined(separator: ", "),
            "url": targetURL
        ])
    }

    func deleteFlow(_ flow: RecordedFlow) {
        savedFlows.removeAll { $0.id == flow.id }
        persistence.saveFlows(savedFlows)
        logger.log("FlowRecorder: deleted flow '\(flow.name)'", category: .persistence, level: .info)
    }

    func selectFlowForPlayback(_ flow: RecordedFlow) {
        selectedFlow = flow
        textboxValues = [:]
        for mapping in flow.textboxMappings {
            textboxValues[mapping.placeholderKey] = ""
        }
        showPlaybackSheet = true
        logger.log("FlowRecorder: selected flow '\(flow.name)' for playback — \(flow.textboxMappings.count) textbox fields to fill", category: .flowRecorder, level: .debug)
    }

    func playSelectedFlow() {
        guard let flow = selectedFlow else {
            logger.log("FlowRecorder: playSelectedFlow — no flow selected", category: .flowRecorder, level: .error)
            return
        }
        guard let webView = activeWebView else {
            logger.log("FlowRecorder: playSelectedFlow — no active webView", category: .flowRecorder, level: .error)
            lastError = "WebView not available for playback"
            return
        }

        showPlaybackSheet = false
        isPlaying = true
        playbackProgress = 0
        playbackActionIndex = 0
        playbackTotalActions = flow.actions.count
        failedActions = 0
        healedActions = 0
        lastError = nil
        statusMessage = "Playing '\(flow.name)'..."

        let emptyFields = textboxValues.filter { $0.value.isEmpty }
        if !emptyFields.isEmpty {
            logger.log("FlowRecorder: playback starting with \(emptyFields.count) empty textbox fields: \(emptyFields.keys.sorted().joined(separator: ", "))", category: .flowRecorder, level: .warning)
        }

        Task {
            await playbackEngine.playFlow(
                flow,
                in: webView,
                textboxValues: textboxValues,
                onProgress: { [weak self] current, total in
                    guard let self else { return }
                    self.playbackActionIndex = current
                    self.playbackTotalActions = total
                    self.playbackProgress = Double(current) / Double(max(total, 1))
                },
                onComplete: { [weak self] success in
                    guard let self else { return }
                    self.isPlaying = false
                    self.failedActions = self.playbackEngine.failedActionIndices.count
                    self.healedActions = self.playbackEngine.healedActionCount
                    if success {
                        if self.failedActions > 0 {
                            self.statusMessage = "Playback complete — \(self.failedActions) failed, \(self.healedActions) healed"
                        } else {
                            self.statusMessage = "Playback complete"
                        }
                    } else {
                        self.statusMessage = "Playback cancelled"
                    }
                    self.logger.log("FlowRecorder: playback finished — failed:\(self.failedActions) healed:\(self.healedActions)", category: .flowRecorder, level: self.failedActions > 0 ? .warning : .success)
                }
            )
        }
    }

    func cancelPlayback() {
        playbackEngine.cancel()
        isPlaying = false
        statusMessage = "Playback cancelled"
    }

    func validateFingerprint() {
        guard let webView = activeWebView else {
            logger.log("FlowRecorder: validateFingerprint — no active webView", category: .fingerprint, level: .warning)
            return
        }
        Task {
            let profile = PPSRStealthService.shared.nextProfile()
            let score = await FingerprintValidationService.shared.validate(in: webView, profileSeed: profile.seed)
            fingerprintScore = score.formattedScore
            if !score.passed {
                logger.log("FlowRecorder: fingerprint FAIL — \(score.formattedScore) signals: \(score.signals.joined(separator: ", "))", category: .fingerprint, level: .error, metadata: [
                    "score": "\(score.totalScore)",
                    "maxSafe": "\(score.maxSafeScore)",
                    "signalCount": "\(score.signals.count)"
                ])
            } else {
                logger.log("FlowRecorder: fingerprint PASS — \(score.formattedScore)", category: .fingerprint, level: .success)
            }
        }
    }

    func exportFlow(_ flow: RecordedFlow) -> Data? {
        let data = persistence.exportFlow(flow)
        if data == nil {
            logger.log("FlowRecorder: export failed for '\(flow.name)'", category: .persistence, level: .error)
        }
        return data
    }

    func importFlow(from data: Data) {
        if let flow = persistence.importFlow(from: data) {
            savedFlows.insert(flow, at: 0)
            persistence.saveFlows(savedFlows)
            statusMessage = "Imported '\(flow.name)'"
            logger.log("FlowRecorder: imported flow '\(flow.name)' — \(flow.actionCount) actions", category: .persistence, level: .success)
        } else {
            lastError = "Failed to import flow — invalid data format"
            statusMessage = "Import failed — invalid data"
            logger.log("FlowRecorder: import failed — could not decode flow data (\(data.count) bytes)", category: .persistence, level: .error)
        }
    }

    var formattedDuration: String {
        let seconds = recordingDurationMs / 1000.0
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return "\(minutes)m \(remaining)s"
    }
}
