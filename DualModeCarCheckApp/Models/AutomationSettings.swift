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

    // MARK: - Login Button Detection
    var loginButtonDetectionMode: ButtonDetectionMode = .hybrid
    var loginButtonTextMatches: [String] = ["Log in", "Login", "Sign in", "Sign In", "Submit", "Continue", "Next", "Go", "Enter"]
    var loginButtonCustomSelector: String = ""
    var loginButtonClickMethod: ButtonClickMethod = .humanClick
    var loginButtonPreClickDelayMs: Int = 150
    var loginButtonPostClickDelayMs: Int = 300
    var loginButtonDoubleClickGuard: Bool = true
    var loginButtonDoubleClickWindowMs: Int = 1500
    var loginButtonScrollIntoView: Bool = true
    var loginButtonWaitForEnabled: Bool = true
    var loginButtonWaitForEnabledTimeoutMs: Int = 5000
    var loginButtonVisibilityCheck: Bool = true
    var loginButtonFocusBeforeClick: Bool = false
    var loginButtonHoverBeforeClick: Bool = true
    var loginButtonHoverDurationMs: Int = 200
    var loginButtonClickOffsetJitter: Bool = true
    var loginButtonClickOffsetMaxPx: Int = 5
    var loginButtonEnterKeyFallback: Bool = true
    var loginButtonFormSubmitFallback: Bool = true
    var loginButtonAriaLabelMatch: Bool = true
    var loginButtonRoleMatch: Bool = true
    var loginButtonImageButtonDetection: Bool = true
    var loginButtonShadowDOMSearch: Bool = true
    var loginButtonIframeSearch: Bool = false
    var loginButtonMinSizePx: Int = 20
    var loginButtonMaxCandidates: Int = 5
    var loginButtonConfidenceThreshold: Double = 0.5
    var loginButtonVisionMLFallback: Bool = true
    var loginButtonOCRFallback: Bool = true
    var loginButtonCoordinateFallback: Bool = true

    // MARK: - Time Delays
    var globalPreActionDelayMs: Int = 0
    var globalPostActionDelayMs: Int = 0
    var preNavigationDelayMs: Int = 100
    var postNavigationDelayMs: Int = 500
    var preTypingDelayMs: Int = 150
    var postTypingDelayMs: Int = 200
    var preSubmitDelayMs: Int = 300
    var postSubmitDelayMs: Int = 500
    var betweenAttemptsDelayMs: Int = 1000
    var betweenCredentialsDelayMs: Int = 500
    var pageStabilizationDelayMs: Int = 800
    var ajaxSettleDelayMs: Int = 1000
    var domMutationSettleMs: Int = 500
    var animationSettleDelayMs: Int = 400
    var redirectFollowDelayMs: Int = 300
    var captchaDetectionDelayMs: Int = 2000
    var errorRecoveryDelayMs: Int = 1500
    var sessionCooldownDelayMs: Int = 0
    var proxyRotationDelayMs: Int = 500
    var vpnReconnectDelayMs: Int = 2000
    var delayRandomizationEnabled: Bool = true
    var delayRandomizationPercent: Int = 25

    // MARK: - Two-Factor / MFA Handling
    var mfaDetectionEnabled: Bool = true
    var mfaWaitTimeoutSeconds: Int = 30
    var mfaAutoSkip: Bool = false
    var mfaMarkAsTempDisabled: Bool = true
    var mfaKeywords: [String] = ["verification", "verify", "code", "2fa", "two-factor", "authenticator", "one-time", "OTP", "security code"]

    // MARK: - CAPTCHA Handling
    var captchaDetectionEnabled: Bool = true
    var captchaAutoSkip: Bool = true
    var captchaMarkAsFailed: Bool = false
    var captchaWaitTimeoutSeconds: Int = 15
    var captchaKeywords: [String] = ["captcha", "recaptcha", "hcaptcha", "robot", "verify you are human", "I'm not a robot"]
    var captchaIframeDetection: Bool = true
    var captchaImageDetection: Bool = true

    // MARK: - Session Management
    var sessionIsolation: SessionIsolationMode = .full
    var clearCookiesBetweenAttempts: Bool = true
    var clearLocalStorageBetweenAttempts: Bool = true
    var clearSessionStorageBetweenAttempts: Bool = true
    var clearCacheBetweenAttempts: Bool = false
    var clearIndexedDBBetweenAttempts: Bool = false
    var freshWebViewPerAttempt: Bool = false
    var reuseWebViewPoolSize: Int = 3
    var webViewMemoryLimitMB: Int = 256
    var webViewJSEnabled: Bool = true
    var webViewImageLoadingEnabled: Bool = true
    var webViewPluginsEnabled: Bool = false

    // MARK: - Error Classification
    var networkErrorAutoRetry: Bool = true
    var sslErrorAutoRetry: Bool = false
    var http403MarkAsBlocked: Bool = true
    var http429RetryAfterSeconds: Int = 60
    var http5xxAutoRetry: Bool = true
    var connectionResetAutoRetry: Bool = true
    var dnsFailureAutoRetry: Bool = true
    var classifyUnknownAsUnsure: Bool = true

    // MARK: - Form Interaction Advanced
    var clearFieldsBeforeTyping: Bool = true
    var clearFieldMethod: FieldClearMethod = .selectAllDelete
    var tabBetweenFields: Bool = false
    var clickFieldBeforeTyping: Bool = true
    var verifyFieldValueAfterTyping: Bool = true
    var retypeOnVerificationFailure: Bool = true
    var maxRetypeAttempts: Int = 2
    var passwordFieldUnmaskCheck: Bool = false
    var autoDetectRememberMe: Bool = true
    var uncheckRememberMe: Bool = true
    var dismissAutofillSuggestions: Bool = true
    var handlePasswordManagers: Bool = true

    // MARK: - Viewport & Window
    var viewportWidth: Int = 1280
    var viewportHeight: Int = 800
    var randomizeViewportSize: Bool = false
    var viewportSizeVariancePx: Int = 50
    var mobileViewportEmulation: Bool = false
    var mobileViewportWidth: Int = 390
    var mobileViewportHeight: Int = 844
    var deviceScaleFactor: Double = 2.0

    // MARK: - Recorded Flow Override
    var urlFlowAssignments: [URLFlowAssignment] = []

    // MARK: - Evaluation Strictness
    nonisolated enum EvaluationStrictness: String, Codable, CaseIterable, Sendable {
        case lenient = "Lenient"
        case normal = "Normal"
        case strict = "Strict"
    }

    nonisolated enum ButtonDetectionMode: String, Codable, CaseIterable, Sendable {
        case cssSelector = "CSS Selector"
        case textMatch = "Text Match"
        case visionML = "Vision ML"
        case hybrid = "Hybrid"
        case coordinateOnly = "Coordinate Only"
    }

    nonisolated enum ButtonClickMethod: String, Codable, CaseIterable, Sendable {
        case humanClick = "Human Click"
        case jsClick = "JS Click"
        case dispatchEvent = "Dispatch Event"
        case formSubmit = "Form Submit"
        case enterKey = "Enter Key"
    }

    nonisolated enum SessionIsolationMode: String, Codable, CaseIterable, Sendable {
        case none = "None"
        case cookies = "Cookies Only"
        case storage = "Storage Only"
        case full = "Full Isolation"
    }

    nonisolated enum FieldClearMethod: String, Codable, CaseIterable, Sendable {
        case selectAllDelete = "Select All + Delete"
        case tripleClickDelete = "Triple Click + Delete"
        case jsValueClear = "JS Value Clear"
        case backspaceLoop = "Backspace Loop"
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
