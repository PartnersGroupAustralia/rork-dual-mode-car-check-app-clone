import Foundation

nonisolated struct AutomationSettings: Codable, Sendable {
    // MARK: - Page Loading
    var pageLoadTimeout: TimeInterval = 30
    var pageLoadRetries: Int = 3
    var retryBackoffMultiplier: Double = 2.0
    var waitForJSRenderMs: Int = 4000
    var fullSessionResetOnFinalRetry: Bool = true

    // MARK: - Field Detection
    var fieldVerificationEnabled: Bool = true
    var fieldVerificationTimeout: TimeInterval = 10
    var autoCalibrationEnabled: Bool = true
    var visionMLCalibrationFallback: Bool = true
    var calibrationConfidenceThreshold: Double = 0.6

    // MARK: - Cookie/Consent
    var dismissCookieNotices: Bool = true
    var cookieDismissDelayMs: Int = 300

    // MARK: - Credential Entry
    var typingSpeedMinMs: Int = 40
    var typingSpeedMaxMs: Int = 120
    var typingJitterEnabled: Bool = true
    var occasionalBackspaceEnabled: Bool = true
    var backspaceProbability: Double = 0.03
    var fieldFocusDelayMs: Int = 200
    var interFieldDelayMs: Int = 400
    var preFillPauseMinMs: Int = 100
    var preFillPauseMaxMs: Int = 500

    // MARK: - Pattern Strategy
    var maxSubmitCycles: Int = 4
    var enabledPatterns: [String] = LoginFormPatternList.allNames
    var patternPriorityOrder: [String] = LoginFormPatternList.defaultPriorityOrder
    var preferCalibratedPatternsFirst: Bool = true
    var patternLearningEnabled: Bool = true
    var fallbackToLegacyFill: Bool = true
    var fallbackToOCRClick: Bool = true
    var fallbackToVisionMLClick: Bool = true
    var fallbackToCoordinateClick: Bool = true

    // MARK: - Submit Behavior
    var submitRetryCount: Int = 3
    var submitRetryDelayMs: Int = 1000
    var waitForResponseSeconds: Double = 5.0
    var rapidPollEnabled: Bool = true
    var rapidPollIntervalMs: Int = 200

    // MARK: - Post-Submit Evaluation
    var welcomeTextDetection: Bool = true
    var redirectDetection: Bool = true
    var errorBannerDetection: Bool = true
    var contentChangeDetection: Bool = true
    var evaluationStrictness: EvaluationStrictness = .normal

    // MARK: - Retry / Requeue
    var requeueOnTimeout: Bool = true
    var requeueOnConnectionFailure: Bool = true
    var requeueOnUnsure: Bool = true
    var requeueOnRedBanner: Bool = true
    var maxRequeueCount: Int = 3
    var cyclePauseMinMs: Int = 500
    var cyclePauseMaxMs: Int = 1500

    // MARK: - Stealth
    var stealthJSInjection: Bool = true
    var fingerprintSpoofing: Bool = true
    var userAgentRotation: Bool = true
    var viewportRandomization: Bool = true
    var webGLNoise: Bool = true
    var canvasNoise: Bool = true
    var audioContextNoise: Bool = true
    var timezoneSpoof: Bool = false
    var languageSpoof: Bool = false

    // MARK: - Screenshot / Debug
    var screenshotOnEveryEval: Bool = true
    var screenshotOnFailure: Bool = true
    var screenshotOnSuccess: Bool = true
    var maxScreenshotRetention: Int = 500
    var capturePageContent: Bool = true

    // MARK: - Concurrency
    var maxConcurrency: Int = 8
    var batchDelayBetweenStartsMs: Int = 0
    var connectionTestBeforeBatch: Bool = false

    // MARK: - Network Per-Mode
    var useAssignedNetworkForTests: Bool = true
    var proxyRotateOnDisabled: Bool = true
    var proxyRotateOnFailure: Bool = false
    var dnsRotatePerRequest: Bool = true
    var vpnConfigRotation: Bool = true

    // MARK: - URL Rotation
    var urlRotationEnabled: Bool = true
    var disableURLAfterConsecutiveFailures: Int = 2
    var reEnableURLAfterSeconds: TimeInterval = 300
    var preferFastestURL: Bool = false
    var smartURLSelection: Bool = false

    // MARK: - Blacklist / Auto-Actions
    var autoBlacklistNoAcc: Bool = true
    var autoBlacklistPermDisabled: Bool = true
    var autoExcludeBlacklist: Bool = true

    // MARK: - Human Simulation
    var humanMouseMovement: Bool = true
    var humanScrollJitter: Bool = true
    var randomPreActionPause: Bool = true
    var preActionPauseMinMs: Int = 50
    var preActionPauseMaxMs: Int = 300
    var gaussianTimingDistribution: Bool = true

    // MARK: - Recorded Flow Override
    var urlFlowAssignments: [URLFlowAssignment] = []

    // MARK: - Evaluation Strictness
    nonisolated enum EvaluationStrictness: String, Codable, CaseIterable, Sendable {
        case lenient = "Lenient"
        case normal = "Normal"
        case strict = "Strict"
    }
}

nonisolated struct URLFlowAssignment: Codable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var urlPattern: String
    var flowId: String
    var flowName: String
    var overridePatternStrategy: Bool = true
    var overrideTypingSpeed: Bool = false
    var overrideStealthSettings: Bool = false
    var overrideSubmitBehavior: Bool = false
    var assignedAt: Date = Date()
}

nonisolated enum LoginFormPatternList {
    static let allNames: [String] = [
        "Tab Navigation",
        "Click-Focus Sequential",
        "ExecCommand Insert",
        "Slow Deliberate Typer",
        "Mobile Touch Burst",
        "Calibrated Direct",
        "Calibrated Typing",
        "Form Submit Direct",
        "Coordinate Click",
        "React Native Setter",
        "Vision ML Coordinate",
    ]

    static let defaultPriorityOrder: [String] = [
        "Calibrated Typing",
        "Calibrated Direct",
        "Tab Navigation",
        "React Native Setter",
        "Form Submit Direct",
        "Coordinate Click",
        "Vision ML Coordinate",
        "Click-Focus Sequential",
        "ExecCommand Insert",
        "Slow Deliberate Typer",
        "Mobile Touch Burst",
    ]
}
