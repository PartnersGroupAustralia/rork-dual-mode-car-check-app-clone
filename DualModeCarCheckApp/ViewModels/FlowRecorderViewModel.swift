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
        savedFlows = persistence.loadFlows()
    }

    func startRecording() {
        guard !isRecording else { return }
        currentActions = []
        recordingDurationMs = 0
        recordingStartTime = ProcessInfo.processInfo.systemUptime * 1000
        isRecording = true
        statusMessage = "Recording..."

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.recordingDurationMs = ProcessInfo.processInfo.systemUptime * 1000 - self.recordingStartTime
            }
        }

        logger.log("FlowRecorder: recording started for \(targetURL)", category: .automation, level: .info)
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil
        statusMessage = "Recording stopped — \(currentActions.count) actions captured"
        logger.log("FlowRecorder: recording stopped — \(currentActions.count) actions, \(String(format: "%.1f", recordingDurationMs / 1000))s", category: .automation, level: .info)

        if !currentActions.isEmpty {
            showSaveSheet = true
        }
    }

    func appendActions(_ actions: [RecordedAction]) {
        currentActions.append(contentsOf: actions)
    }

    func handlePageLoaded(_ title: String) {
        pageTitle = title
        logger.log("FlowRecorder: page loaded — \(title)", category: .webView, level: .debug)
        validateFingerprint()
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
        logger.log("FlowRecorder: saved flow '\(name)' — \(flow.actionCount) actions", category: .persistence, level: .success)
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
    }

    func playSelectedFlow() {
        guard let flow = selectedFlow, let webView = activeWebView else { return }
        showPlaybackSheet = false
        isPlaying = true
        playbackProgress = 0
        playbackActionIndex = 0
        playbackTotalActions = flow.actions.count
        statusMessage = "Playing '\(flow.name)'..."

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
                    self.statusMessage = success ? "Playback complete" : "Playback cancelled"
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
        guard let webView = activeWebView else { return }
        Task {
            let profile = PPSRStealthService.shared.nextProfile()
            let score = await FingerprintValidationService.shared.validate(in: webView, profileSeed: profile.seed)
            fingerprintScore = score.formattedScore
            if !score.passed {
                logger.log("FlowRecorder: fingerprint FAIL — \(score.formattedScore) signals: \(score.signals.joined(separator: ", "))", category: .fingerprint, level: .error)
            } else {
                logger.log("FlowRecorder: fingerprint PASS — \(score.formattedScore)", category: .fingerprint, level: .success)
            }
        }
    }

    func exportFlow(_ flow: RecordedFlow) -> Data? {
        persistence.exportFlow(flow)
    }

    func importFlow(from data: Data) {
        if let flow = persistence.importFlow(from: data) {
            savedFlows.insert(flow, at: 0)
            persistence.saveFlows(savedFlows)
            statusMessage = "Imported '\(flow.name)'"
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
