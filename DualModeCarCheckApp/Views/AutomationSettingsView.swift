import SwiftUI

struct AutomationSettingsView: View {
    @Bindable var vm: LoginViewModel
    @State private var showFlowAssignment: Bool = false
    @State private var showPatternReorder: Bool = false

    private var accentColor: Color {
        vm.isIgnitionMode ? .orange : .green
    }

    var body: some View {
        List {
            pageLoadingSection
            fieldDetectionSection
            cookieConsentSection
            credentialEntrySection
            patternStrategySection
            submitBehaviorSection
            postSubmitEvalSection
            retryRequeueSection
            stealthDetailSection
            humanSimulationSection
            screenshotDebugSection
            concurrencyDetailSection
            networkPerModeSection
            urlRotationDetailSection
            blacklistAutoSection
            flowAssignmentSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Automation Config")
        .sheet(isPresented: $showFlowAssignment) {
            NavigationStack {
                URLFlowAssignmentView(vm: vm)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showPatternReorder) {
            NavigationStack {
                PatternPriorityView(settings: $vm.automationSettings)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
    }

    // MARK: - Page Loading

    private var pageLoadingSection: some View {
        Section {
            HStack {
                Image(systemName: "globe").foregroundStyle(.blue)
                Text("Page Load Timeout")
                Spacer()
                Picker("", selection: Binding(
                    get: { Int(vm.automationSettings.pageLoadTimeout) },
                    set: { vm.automationSettings.pageLoadTimeout = TimeInterval($0) }
                )) {
                    Text("15s").tag(15)
                    Text("20s").tag(20)
                    Text("30s").tag(30)
                    Text("45s").tag(45)
                    Text("60s").tag(60)
                }
                .pickerStyle(.menu)
            }

            Stepper("Load Retries: \(vm.automationSettings.pageLoadRetries)", value: $vm.automationSettings.pageLoadRetries, in: 1...10)

            HStack {
                Text("Retry Backoff Multiplier")
                Spacer()
                Picker("", selection: $vm.automationSettings.retryBackoffMultiplier) {
                    Text("1.0x").tag(1.0)
                    Text("1.5x").tag(1.5)
                    Text("2.0x").tag(2.0)
                    Text("3.0x").tag(3.0)
                }
                .pickerStyle(.menu)
            }

            Stepper("JS Render Wait: \(vm.automationSettings.waitForJSRenderMs)ms", value: $vm.automationSettings.waitForJSRenderMs, in: 1000...15000, step: 500)

            Toggle(isOn: $vm.automationSettings.fullSessionResetOnFinalRetry) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Reset on Final Retry")
                    Text("Tear down and rebuild WKWebView on last attempt").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)
        } header: {
            Label("Page Loading", systemImage: "globe")
        } footer: {
            Text("Controls how pages are loaded and retried. Backoff multiplier increases wait time between retries.")
        }
    }

    // MARK: - Field Detection

    private var fieldDetectionSection: some View {
        Section {
            Toggle(isOn: $vm.automationSettings.fieldVerificationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Field Verification")
                    Text("Verify email/password fields exist before filling").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            if vm.automationSettings.fieldVerificationEnabled {
                Stepper("Verification Timeout: \(Int(vm.automationSettings.fieldVerificationTimeout))s", value: $vm.automationSettings.fieldVerificationTimeout, in: 3...30)
            }

            Toggle(isOn: $vm.automationSettings.autoCalibrationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Calibration")
                    Text("Probe DOM to map CSS selectors automatically").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            Toggle(isOn: $vm.automationSettings.visionMLCalibrationFallback) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vision ML Fallback")
                    Text("Use screenshot OCR if DOM calibration fails").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(.purple)

            HStack {
                Text("Calibration Confidence Threshold")
                Spacer()
                Text("\(Int(vm.automationSettings.calibrationConfidenceThreshold * 100))%")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $vm.automationSettings.calibrationConfidenceThreshold, in: 0.3...1.0, step: 0.05)
                .tint(accentColor)
        } header: {
            Label("Field Detection", systemImage: "textformat.alt")
        } footer: {
            Text("How login fields are discovered. Higher confidence threshold = stricter calibration acceptance.")
        }
    }

    // MARK: - Cookie/Consent

    private var cookieConsentSection: some View {
        Section {
            Toggle(isOn: $vm.automationSettings.dismissCookieNotices) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dismiss Cookie Notices")
                    Text("Auto-dismiss GDPR/cookie banners before login").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            if vm.automationSettings.dismissCookieNotices {
                Stepper("Post-Dismiss Delay: \(vm.automationSettings.cookieDismissDelayMs)ms", value: $vm.automationSettings.cookieDismissDelayMs, in: 100...2000, step: 100)
            }
        } header: {
            Label("Cookie / Consent", systemImage: "hand.raised.fill")
        }
    }

    // MARK: - Credential Entry

    private var credentialEntrySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Typing Speed Range").font(.subheadline)
                HStack {
                    Text("\(vm.automationSettings.typingSpeedMinMs)ms")
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text("\(vm.automationSettings.typingSpeedMaxMs)ms")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Min").font(.caption2).foregroundStyle(.tertiary)
                        Stepper("\(vm.automationSettings.typingSpeedMinMs)", value: $vm.automationSettings.typingSpeedMinMs, in: 10...200, step: 10)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading) {
                        Text("Max").font(.caption2).foregroundStyle(.tertiary)
                        Stepper("\(vm.automationSettings.typingSpeedMaxMs)", value: $vm.automationSettings.typingSpeedMaxMs, in: 50...500, step: 10)
                            .labelsHidden()
                    }
                }
            }

            Toggle(isOn: $vm.automationSettings.typingJitterEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Typing Jitter")
                    Text("Gaussian randomization on keystroke timing").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            Toggle(isOn: $vm.automationSettings.occasionalBackspaceEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Occasional Backspace")
                    Text("Simulate human typos with correction").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            if vm.automationSettings.occasionalBackspaceEnabled {
                HStack {
                    Text("Backspace Probability")
                    Spacer()
                    Text("\(Int(vm.automationSettings.backspaceProbability * 100))%")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $vm.automationSettings.backspaceProbability, in: 0.01...0.15, step: 0.01)
                    .tint(accentColor)
            }

            Stepper("Focus Delay: \(vm.automationSettings.fieldFocusDelayMs)ms", value: $vm.automationSettings.fieldFocusDelayMs, in: 50...2000, step: 50)
            Stepper("Inter-Field Delay: \(vm.automationSettings.interFieldDelayMs)ms", value: $vm.automationSettings.interFieldDelayMs, in: 100...3000, step: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pre-Fill Pause Range").font(.subheadline)
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Min").font(.caption2).foregroundStyle(.tertiary)
                        Stepper("\(vm.automationSettings.preFillPauseMinMs)ms", value: $vm.automationSettings.preFillPauseMinMs, in: 0...1000, step: 50)
                    }
                    VStack(alignment: .leading) {
                        Text("Max").font(.caption2).foregroundStyle(.tertiary)
                        Stepper("\(vm.automationSettings.preFillPauseMaxMs)ms", value: $vm.automationSettings.preFillPauseMaxMs, in: 100...3000, step: 50)
                    }
                }
            }
        } header: {
            Label("Credential Entry", systemImage: "keyboard")
        } footer: {
            Text("Fine-tune keystroke timing, delays, and human-like typo simulation for form filling.")
        }
    }

    // MARK: - Pattern Strategy

    private var patternStrategySection: some View {
        Section {
            Stepper("Max Submit Cycles: \(vm.automationSettings.maxSubmitCycles)", value: $vm.automationSettings.maxSubmitCycles, in: 1...10)

            Toggle(isOn: $vm.automationSettings.preferCalibratedPatternsFirst) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prefer Calibrated Patterns")
                    Text("Try calibrated selectors before generic patterns").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            Toggle(isOn: $vm.automationSettings.patternLearningEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pattern Learning")
                    Text("Remember which patterns work per URL").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(.purple)

            Button {
                showPatternReorder = true
            } label: {
                HStack {
                    Image(systemName: "list.number").foregroundStyle(accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pattern Priority Order")
                        Text("\(vm.automationSettings.enabledPatterns.count) enabled, \(vm.automationSettings.patternPriorityOrder.count) ordered").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }

            Group {
                Toggle("Fallback: Legacy Fill", isOn: $vm.automationSettings.fallbackToLegacyFill)
                Toggle("Fallback: OCR Click", isOn: $vm.automationSettings.fallbackToOCRClick)
                Toggle("Fallback: Vision ML Click", isOn: $vm.automationSettings.fallbackToVisionMLClick)
                Toggle("Fallback: Coordinate Click", isOn: $vm.automationSettings.fallbackToCoordinateClick)
            }
            .tint(accentColor)
        } header: {
            Label("Pattern Strategy", systemImage: "wand.and.rays")
        } footer: {
            Text("Controls form-filling patterns, fallback chains, and learning. Cycles retry with different strategies if prior ones fail.")
        }
    }

    // MARK: - Submit Behavior

    private var submitBehaviorSection: some View {
        Section {
            Stepper("Submit Retries: \(vm.automationSettings.submitRetryCount)", value: $vm.automationSettings.submitRetryCount, in: 1...10)
            Stepper("Retry Delay: \(vm.automationSettings.submitRetryDelayMs)ms", value: $vm.automationSettings.submitRetryDelayMs, in: 200...5000, step: 200)

            HStack {
                Text("Wait for Response")
                Spacer()
                Picker("", selection: $vm.automationSettings.waitForResponseSeconds) {
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                    Text("8s").tag(8.0)
                    Text("10s").tag(10.0)
                    Text("15s").tag(15.0)
                }
                .pickerStyle(.menu)
            }

            Toggle(isOn: $vm.automationSettings.rapidPollEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rapid Welcome Poll")
                    Text("Fast-check for welcome text/redirect after submit").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            if vm.automationSettings.rapidPollEnabled {
                Stepper("Poll Interval: \(vm.automationSettings.rapidPollIntervalMs)ms", value: $vm.automationSettings.rapidPollIntervalMs, in: 50...1000, step: 50)
            }
        } header: {
            Label("Submit Behavior", systemImage: "paperplane.fill")
        } footer: {
            Text("How login submissions are triggered and monitored for results.")
        }
    }

    // MARK: - Post-Submit Evaluation

    private var postSubmitEvalSection: some View {
        Section {
            Toggle("Welcome Text Detection", isOn: $vm.automationSettings.welcomeTextDetection).tint(accentColor)
            Toggle("Redirect Detection", isOn: $vm.automationSettings.redirectDetection).tint(accentColor)
            Toggle("Error Banner Detection", isOn: $vm.automationSettings.errorBannerDetection).tint(accentColor)
            Toggle("Content Change Detection", isOn: $vm.automationSettings.contentChangeDetection).tint(accentColor)
            Toggle("Capture Page Content", isOn: $vm.automationSettings.capturePageContent).tint(accentColor)

            Picker("Evaluation Strictness", selection: $vm.automationSettings.evaluationStrictness) {
                ForEach(AutomationSettings.EvaluationStrictness.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
        } header: {
            Label("Post-Submit Evaluation", systemImage: "checklist.checked")
        } footer: {
            Text("Lenient = more likely to report success. Strict = requires stronger signals. Normal = balanced.")
        }
    }

    // MARK: - Retry / Requeue

    private var retryRequeueSection: some View {
        Section {
            Toggle("Requeue on Timeout", isOn: $vm.automationSettings.requeueOnTimeout).tint(accentColor)
            Toggle("Requeue on Connection Failure", isOn: $vm.automationSettings.requeueOnConnectionFailure).tint(accentColor)
            Toggle("Requeue on Unsure", isOn: $vm.automationSettings.requeueOnUnsure).tint(accentColor)
            Toggle("Requeue on Red Banner", isOn: $vm.automationSettings.requeueOnRedBanner).tint(accentColor)

            Stepper("Max Requeue Count: \(vm.automationSettings.maxRequeueCount)", value: $vm.automationSettings.maxRequeueCount, in: 0...20)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cycle Pause Range").font(.subheadline)
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Min").font(.caption2).foregroundStyle(.tertiary)
                        Stepper("\(vm.automationSettings.cyclePauseMinMs)ms", value: $vm.automationSettings.cyclePauseMinMs, in: 100...5000, step: 100)
                    }
                    VStack(alignment: .leading) {
                        Text("Max").font(.caption2).foregroundStyle(.tertiary)
                        Stepper("\(vm.automationSettings.cyclePauseMaxMs)ms", value: $vm.automationSettings.cyclePauseMaxMs, in: 200...10000, step: 100)
                    }
                }
            }
        } header: {
            Label("Retry / Requeue", systemImage: "arrow.counterclockwise")
        } footer: {
            Text("Controls when failed tests are requeued vs marked final, and pauses between retry cycles.")
        }
    }

    // MARK: - Stealth Detail

    private var stealthDetailSection: some View {
        Section {
            Toggle("Stealth JS Injection", isOn: $vm.automationSettings.stealthJSInjection).tint(.purple)
            Toggle("Fingerprint Spoofing", isOn: $vm.automationSettings.fingerprintSpoofing).tint(.purple)
            Toggle("User-Agent Rotation", isOn: $vm.automationSettings.userAgentRotation).tint(.purple)
            Toggle("Viewport Randomization", isOn: $vm.automationSettings.viewportRandomization).tint(.purple)
            Toggle("WebGL Noise", isOn: $vm.automationSettings.webGLNoise).tint(.purple)
            Toggle("Canvas Noise", isOn: $vm.automationSettings.canvasNoise).tint(.purple)
            Toggle("AudioContext Noise", isOn: $vm.automationSettings.audioContextNoise).tint(.purple)
            Toggle("Timezone Spoof", isOn: $vm.automationSettings.timezoneSpoof).tint(.purple)
            Toggle("Language Spoof", isOn: $vm.automationSettings.languageSpoof).tint(.purple)
        } header: {
            Label("Stealth Detail", systemImage: "eye.slash.fill")
        } footer: {
            Text("Granular control over individual stealth/anti-fingerprint techniques. These are sub-options of the global stealth toggle.")
        }
    }

    // MARK: - Human Simulation

    private var humanSimulationSection: some View {
        Section {
            Toggle("Human Mouse Movement", isOn: $vm.automationSettings.humanMouseMovement).tint(accentColor)
            Toggle("Human Scroll Jitter", isOn: $vm.automationSettings.humanScrollJitter).tint(accentColor)
            Toggle("Random Pre-Action Pause", isOn: $vm.automationSettings.randomPreActionPause).tint(accentColor)

            if vm.automationSettings.randomPreActionPause {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pre-Action Pause Range").font(.subheadline)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Min").font(.caption2).foregroundStyle(.tertiary)
                            Stepper("\(vm.automationSettings.preActionPauseMinMs)ms", value: $vm.automationSettings.preActionPauseMinMs, in: 0...1000, step: 10)
                        }
                        VStack(alignment: .leading) {
                            Text("Max").font(.caption2).foregroundStyle(.tertiary)
                            Stepper("\(vm.automationSettings.preActionPauseMaxMs)ms", value: $vm.automationSettings.preActionPauseMaxMs, in: 50...2000, step: 10)
                        }
                    }
                }
            }

            Toggle(isOn: $vm.automationSettings.gaussianTimingDistribution) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gaussian Timing Distribution")
                    Text("Bell-curve randomization instead of uniform").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)
        } header: {
            Label("Human Simulation", systemImage: "figure.walk")
        } footer: {
            Text("Controls how human-like the automation behaves. Gaussian timing produces more realistic patterns.")
        }
    }

    // MARK: - Screenshot / Debug

    private var screenshotDebugSection: some View {
        Section {
            Toggle("Screenshot Every Evaluation", isOn: $vm.automationSettings.screenshotOnEveryEval).tint(.orange)
            Toggle("Screenshot on Failure", isOn: $vm.automationSettings.screenshotOnFailure).tint(.orange)
            Toggle("Screenshot on Success", isOn: $vm.automationSettings.screenshotOnSuccess).tint(.orange)
            Stepper("Max Retention: \(vm.automationSettings.maxScreenshotRetention)", value: $vm.automationSettings.maxScreenshotRetention, in: 50...2000, step: 50)
        } header: {
            Label("Screenshot / Debug", systemImage: "camera.viewfinder")
        } footer: {
            Text("Controls when debug screenshots are captured and how many are retained in memory.")
        }
    }

    // MARK: - Concurrency Detail

    private var concurrencyDetailSection: some View {
        Section {
            Stepper("Max Concurrency: \(vm.automationSettings.maxConcurrency)", value: $vm.automationSettings.maxConcurrency, in: 1...16)
            Stepper("Batch Start Delay: \(vm.automationSettings.batchDelayBetweenStartsMs)ms", value: $vm.automationSettings.batchDelayBetweenStartsMs, in: 0...5000, step: 100)

            Toggle(isOn: $vm.automationSettings.connectionTestBeforeBatch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Test Before Batch")
                    Text("Verify connectivity before starting a batch run").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)
        } header: {
            Label("Concurrency", systemImage: "square.stack.3d.up.fill")
        } footer: {
            Text("Controls parallel session count and staggered batch start timing.")
        }
    }

    // MARK: - Network Per-Mode

    private var networkPerModeSection: some View {
        Section {
            Toggle(isOn: $vm.automationSettings.useAssignedNetworkForTests) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Assigned Network for Tests")
                    Text("Connection tests use the mode's configured network (proxy/VPN/DNS)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

            Toggle("Proxy Rotate on Disabled", isOn: $vm.automationSettings.proxyRotateOnDisabled).tint(.blue)
            Toggle("Proxy Rotate on Failure", isOn: $vm.automationSettings.proxyRotateOnFailure).tint(.blue)
            Toggle("DNS Rotate Per Request", isOn: $vm.automationSettings.dnsRotatePerRequest).tint(.cyan)
            Toggle("VPN Config Rotation", isOn: $vm.automationSettings.vpnConfigRotation).tint(.indigo)
        } header: {
            Label("Network Per-Mode", systemImage: "network")
        } footer: {
            Text("Ensures URL testing and automation use the network settings assigned to Joe or Ignition mode.")
        }
    }

    // MARK: - URL Rotation Detail

    private var urlRotationDetailSection: some View {
        Section {
            Toggle("URL Rotation Enabled", isOn: $vm.automationSettings.urlRotationEnabled).tint(accentColor)
            Stepper("Disable After \(vm.automationSettings.disableURLAfterConsecutiveFailures) Failures", value: $vm.automationSettings.disableURLAfterConsecutiveFailures, in: 1...10)

            HStack {
                Text("Re-Enable After")
                Spacer()
                Picker("", selection: Binding(
                    get: { Int(vm.automationSettings.reEnableURLAfterSeconds) },
                    set: { vm.automationSettings.reEnableURLAfterSeconds = TimeInterval($0) }
                )) {
                    Text("1 min").tag(60)
                    Text("5 min").tag(300)
                    Text("15 min").tag(900)
                    Text("30 min").tag(1800)
                    Text("Never").tag(0)
                }
                .pickerStyle(.menu)
            }

            Toggle(isOn: $vm.automationSettings.preferFastestURL) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prefer Fastest URL")
                    Text("Weight URL selection by response time").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            Toggle(isOn: $vm.automationSettings.smartURLSelection) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart URL Selection")
                    Text("Combine success rate + speed for URL priority").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(.purple)
        } header: {
            Label("URL Rotation", systemImage: "arrow.triangle.2.circlepath")
        } footer: {
            Text("Fine-grained URL rotation behavior including automatic disable/re-enable and performance-based selection.")
        }
    }

    // MARK: - Blacklist / Auto

    private var blacklistAutoSection: some View {
        Section {
            Toggle("Auto-Blacklist No Account", isOn: $vm.automationSettings.autoBlacklistNoAcc).tint(.red)
            Toggle("Auto-Blacklist Perm Disabled", isOn: $vm.automationSettings.autoBlacklistPermDisabled).tint(.red)
            Toggle("Auto-Exclude Blacklisted on Import", isOn: $vm.automationSettings.autoExcludeBlacklist).tint(.orange)
        } header: {
            Label("Blacklist / Auto-Actions", systemImage: "hand.raised.slash.fill")
        } footer: {
            Text("Automatic blacklisting and exclusion rules applied during testing and import.")
        }
    }

    // MARK: - Flow Assignment

    private var flowAssignmentSection: some View {
        Section {
            let assignmentCount = vm.automationSettings.urlFlowAssignments.count
            Button {
                showFlowAssignment = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("URL Flow Assignments")
                        Text("\(assignmentCount) URL\(assignmentCount == 1 ? "" : "s") with assigned flows").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }

            if !vm.automationSettings.urlFlowAssignments.isEmpty {
                ForEach(vm.automationSettings.urlFlowAssignments) { assignment in
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.caption).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(assignment.urlPattern)
                                .font(.system(.caption, design: .monospaced, weight: .medium))
                                .lineLimit(1)
                            Text("→ \(assignment.flowName)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if assignment.overridePatternStrategy {
                            Text("OVERRIDE")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color.red.opacity(0.12)).clipShape(Capsule())
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            vm.automationSettings.urlFlowAssignments.removeAll { $0.id == assignment.id }
                            vm.persistAutomationSettings()
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }

            Button(role: .destructive) {
                vm.automationSettings = AutomationSettings()
                vm.persistAutomationSettings()
            } label: {
                Label("Reset All to Defaults", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Label("Recorded Flow Overrides", systemImage: "record.circle")
        } footer: {
            Text("Assign a recorded flow to specific URLs. When a URL matches, the recorded flow is played instead of the normal pattern strategy. This overrides conflicting settings.")
        }
    }
}

// MARK: - Pattern Priority View

struct PatternPriorityView: View {
    @Binding var settings: AutomationSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(settings.patternPriorityOrder, id: \.self) { name in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.system(.subheadline, design: .monospaced))

                        Spacer()

                        let isEnabled = settings.enabledPatterns.contains(name)
                        Button {
                            if isEnabled {
                                settings.enabledPatterns.removeAll { $0 == name }
                            } else {
                                settings.enabledPatterns.append(name)
                            }
                        } label: {
                            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isEnabled ? .green : .secondary)
                        }
                    }
                }
                .onMove { source, destination in
                    settings.patternPriorityOrder.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("Drag to reorder. Tap circle to enable/disable.")
            } footer: {
                Text("Patterns are tried in this order during login cycles. Disabled patterns are skipped entirely.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pattern Priority")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .environment(\.editMode, .constant(.active))
    }
}

// MARK: - URL Flow Assignment View

struct URLFlowAssignmentView: View {
    let vm: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: String = ""
    @State private var selectedFlowId: String = ""
    @State private var overridePattern: Bool = true
    @State private var overrideTyping: Bool = false
    @State private var overrideStealth: Bool = false
    @State private var overrideSubmit: Bool = false

    private var availableFlows: [RecordedFlow] {
        FlowPersistenceService.shared.loadFlows()
    }

    private var availableURLs: [LoginURLRotationService.RotatingURL] {
        vm.urlRotation.activeURLs
    }

    var body: some View {
        List {
            Section {
                Picker("URL", selection: $selectedURL) {
                    Text("Select URL…").tag("")
                    ForEach(availableURLs, id: \.id) { url in
                        Text(url.host)
                            .font(.system(.caption, design: .monospaced))
                            .tag(url.urlString)
                    }
                }

                Picker("Recorded Flow", selection: $selectedFlowId) {
                    Text("Select Flow…").tag("")
                    ForEach(availableFlows) { flow in
                        Text("\(flow.name) (\(flow.actionCount) actions)")
                            .tag(flow.id)
                    }
                }
            } header: {
                Text("New Assignment")
            }

            Section {
                Toggle("Override Pattern Strategy", isOn: $overridePattern).tint(.red)
                Toggle("Override Typing Speed", isOn: $overrideTyping).tint(.orange)
                Toggle("Override Stealth Settings", isOn: $overrideStealth).tint(.purple)
                Toggle("Override Submit Behavior", isOn: $overrideSubmit).tint(.blue)
            } header: {
                Text("Override Scope")
            } footer: {
                Text("When overrides are enabled, the recorded flow replaces the corresponding automation settings for this URL.")
            }

            Section {
                Button {
                    guard !selectedURL.isEmpty, !selectedFlowId.isEmpty else { return }
                    let flowName = availableFlows.first(where: { $0.id == selectedFlowId })?.name ?? "Unknown"

                    vm.automationSettings.urlFlowAssignments.removeAll { $0.urlPattern == selectedURL }

                    let assignment = URLFlowAssignment(
                        urlPattern: selectedURL,
                        flowId: selectedFlowId,
                        flowName: flowName,
                        overridePatternStrategy: overridePattern,
                        overrideTypingSpeed: overrideTyping,
                        overrideStealthSettings: overrideStealth,
                        overrideSubmitBehavior: overrideSubmit
                    )
                    vm.automationSettings.urlFlowAssignments.append(assignment)
                    vm.persistAutomationSettings()
                    vm.log("Assigned flow '\(flowName)' to \(selectedURL)", level: .success)
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Label("Assign Flow", systemImage: "link.badge.plus")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(selectedURL.isEmpty || selectedFlowId.isEmpty)
                .listRowBackground(selectedURL.isEmpty || selectedFlowId.isEmpty ? Color.green.opacity(0.3) : Color.green)
                .foregroundStyle(.white)
            }

            if !vm.automationSettings.urlFlowAssignments.isEmpty {
                Section("Existing Assignments") {
                    ForEach(vm.automationSettings.urlFlowAssignments) { assignment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(assignment.urlPattern)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                Text(assignment.flowName).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                if assignment.overridePatternStrategy {
                                    overrideBadge("Pattern", color: .red)
                                }
                                if assignment.overrideTypingSpeed {
                                    overrideBadge("Typing", color: .orange)
                                }
                                if assignment.overrideStealthSettings {
                                    overrideBadge("Stealth", color: .purple)
                                }
                                if assignment.overrideSubmitBehavior {
                                    overrideBadge("Submit", color: .blue)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                vm.automationSettings.urlFlowAssignments.removeAll { $0.id == assignment.id }
                                vm.persistAutomationSettings()
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Flow Assignments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func overrideBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }
}
