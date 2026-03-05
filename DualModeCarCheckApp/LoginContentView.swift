import SwiftUI
import UniformTypeIdentifiers

struct LoginContentView: View {
    let initialMode: ActiveAppMode
    @State private var vm = LoginViewModel()
    @State private var initialModeApplied: Bool = false

    private var accentColor: Color {
        vm.isIgnitionMode ? .orange : .green
    }

    private var loginSettingsHash: String {
        "\(vm.appearanceMode.rawValue)-\(vm.debugMode)-\(vm.maxConcurrency)-\(vm.stealthEnabled)-\(vm.targetSite.rawValue)"
    }

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: vm.isIgnitionMode ? "flame.fill" : "bolt.shield.fill") {
                NavigationStack {
                    LoginDashboardContentView(vm: vm)
                }
                .overlay(alignment: .bottomLeading) { MainMenuButton() }
            }

            Tab("Credentials", systemImage: "person.text.rectangle") {
                NavigationStack {
                    LoginCredentialsListView(vm: vm)
                        .navigationDestination(for: String.self) { credId in
                            if let cred = vm.credentials.first(where: { $0.id == credId }) {
                                LoginCredentialDetailView(credential: cred, vm: vm)
                            }
                        }
                }
                .overlay(alignment: .bottomLeading) { MainMenuButton() }
            }

            Tab("Working", systemImage: "checkmark.shield.fill") {
                NavigationStack {
                    LoginWorkingListView(vm: vm)
                }
                .overlay(alignment: .bottomLeading) { MainMenuButton() }
            }

            Tab("Sessions", systemImage: "rectangle.stack") {
                NavigationStack {
                    LoginSessionMonitorContentView(vm: vm)
                }
                .overlay(alignment: .bottomLeading) { MainMenuButton() }
            }

            Tab("More", systemImage: "ellipsis.circle") {
                NavigationStack {
                    LoginMoreMenuView(vm: vm)
                }
                .overlay(alignment: .bottomLeading) { MainMenuButton() }
            }
        }
        .tint(accentColor)
        .preferredColorScheme(vm.effectiveColorScheme)
        .onAppear {
            if !initialModeApplied {
                initialModeApplied = true
                switch initialMode {
                case .joe: vm.setSiteMode(.joe)
                case .ignition: vm.setSiteMode(.ignition)
                case .ppsr, .superTest, .debugLog, .flowRecorder: break
                }
            }
        }
        .onChange(of: vm.credentials.count) { _, _ in
            vm.persistCredentials()
        }
        .onChange(of: loginSettingsHash) { _, _ in
            vm.persistSettings()
        }
        .onChange(of: vm.isRunning) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .alert("Batch Results", isPresented: $vm.showBatchResultPopup) {
            Button("OK") { vm.showBatchResultPopup = false }
        } message: {
            if let result = vm.lastBatchResult {
                Text("Working: \(result.working) (\(result.alivePercentage)%)\nFailed: \(result.dead)\nRequeued: \(result.requeued)\nTotal: \(result.total)")
            } else {
                Text("No results available")
            }
        }
        .alert("Unusual Failures Detected", isPresented: $vm.showUnusualFailureAlert) {
            Button("Stop After Current", role: .destructive) {
                vm.stopAfterCurrent()
                vm.consecutiveUnusualFailures = 0
            }
            Button("Continue Testing", role: .cancel) {
                vm.consecutiveUnusualFailures = 0
            }
        } message: {
            Text("Multiple consecutive unusual/unrecognized failures detected.\n\n\(vm.unusualFailureMessage)\n\nWould you like to stop testing?")
        }
    }
}

// MARK: - Dashboard

struct LoginDashboardContentView: View {
    let vm: LoginViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                statusHeader
                dashboardActionButtons
                if vm.isRunning {
                    testingBanner
                    queueControls
                }
                if vm.stealthEnabled {
                    stealthBadge
                }
                statsRow
                if !vm.untestedCredentials.isEmpty {
                    credentialSection(title: "Queued — Untested", creds: Array(vm.untestedCredentials.prefix(50)), color: .secondary, icon: "clock.fill")
                }
                if !vm.testingCredentials.isEmpty {
                    credentialSection(title: "Testing Now", creds: vm.testingCredentials, color: .green, icon: "arrow.triangle.2.circlepath")
                }
                if !vm.noAccCredentials.isEmpty {
                    noAccSection
                }
                if !vm.permDisabledCredentials.isEmpty {
                    permDisabledSection
                }
                if !vm.tempDisabledCredentials.isEmpty {
                    tempDisabledSection
                }
                if !vm.unsureCredentials.isEmpty {
                    unsureSection
                }
                if vm.credentials.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .task {
            await vm.testConnection()
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: vm.urlRotation.currentIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(vm.isIgnitionMode ? .orange : .green)
                    .symbolEffect(.pulse, isActive: vm.isRunning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.urlRotation.currentSiteName)
                        .font(.title3.bold())
                    Text("\(vm.urlRotation.enabledURLs.count)/\(vm.urlRotation.activeURLs.count) URLs active")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                connectionBadge
            }

            dualModeToggle
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var dualModeToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption.bold())
                .foregroundStyle(vm.dualSiteMode ? .cyan : .secondary)
            Toggle(isOn: Binding(
                get: { vm.dualSiteMode },
                set: { newVal in
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        if newVal {
                            vm.setSiteMode(.dual)
                        } else {
                            vm.setSiteMode(vm.isIgnitionMode ? .ignition : .joe)
                        }
                    }
                }
            )) {
                Text("Dual Mode")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.cyan)
        }
        .padding(10)
        .background(vm.dualSiteMode ? Color.cyan.opacity(0.08) : Color(.tertiarySystemFill))
        .clipShape(.rect(cornerRadius: 10))
        .sensoryFeedback(.impact(weight: .medium), trigger: vm.dualSiteMode)
    }

    private var connectionBadge: some View {
        Button {
            Task { await vm.testConnection() }
        } label: {
            HStack(spacing: 4) {
                if vm.connectionStatus == .connecting {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(connectionColor).frame(width: 7, height: 7)
                }
                Text(vm.connectionStatus == .connecting ? "Testing..." : vm.connectionStatus.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(connectionColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(connectionColor.opacity(0.12))
            .clipShape(Capsule())
        }
        .sensoryFeedback(.impact(weight: .light), trigger: vm.connectionStatus.rawValue)
    }

    private var connectionColor: Color {
        switch vm.connectionStatus {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .secondary
        case .error: .red
        }
    }

    private var accentColor: Color {
        vm.isIgnitionMode ? .orange : .green
    }

    private var stealthBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill").font(.caption).foregroundStyle(.purple)
            Text("Ultra Stealth + Full Wipe").font(.caption.bold()).foregroundStyle(.purple)
            Spacer()
            Text("Rotating UA + Fingerprints").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var testingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().tint(accentColor)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Testing in Progress").font(.subheadline.bold()).foregroundStyle(accentColor)
                    if vm.isPaused {
                        Text("PAUSED")
                            .font(.system(.caption2, design: .monospaced, weight: .heavy))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15)).clipShape(Capsule())
                    }
                    if vm.isStopping {
                        Text("STOPPING")
                            .font(.system(.caption2, design: .monospaced, weight: .heavy))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15)).clipShape(Capsule())
                    }
                }
                Text("\(vm.activeTestCount) active · \(vm.untestedCredentials.count) queued · \(vm.testingCredentials.count) testing")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.green.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var queueControls: some View {
        HStack(spacing: 10) {
            if vm.isPaused {
                Button { vm.resumeQueue() } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.green.opacity(0.15)).foregroundStyle(.green).clipShape(.rect(cornerRadius: 12))
                }
            } else {
                Button { vm.pauseQueue() } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.orange.opacity(0.15)).foregroundStyle(.orange).clipShape(.rect(cornerRadius: 12))
                }
            }
            Button { vm.stopQueue() } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.red.opacity(0.15)).foregroundStyle(.red).clipShape(.rect(cornerRadius: 12))
            }
            .disabled(vm.isStopping)
        }
    }

    private var statsRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LoginMiniStat(value: "\(vm.workingCredentials.count)", label: "Working", color: .green, icon: "checkmark.circle.fill")
                LoginMiniStat(value: "\(vm.untestedCredentials.count)", label: "Queued", color: .secondary, icon: "clock")
                LoginMiniStat(value: "\(vm.noAccCredentials.count)", label: "No Acc", color: .red, icon: "xmark.circle.fill")
            }
            HStack(spacing: 10) {
                LoginMiniStat(value: "\(vm.permDisabledCredentials.count)", label: "Perm Dis", color: .red.opacity(0.7), icon: "lock.slash.fill")
                LoginMiniStat(value: "\(vm.tempDisabledCredentials.count)", label: "Temp Dis", color: .orange, icon: "clock.badge.exclamationmark")
                LoginMiniStat(value: "\(vm.unsureCredentials.count)", label: "Unsure", color: .yellow, icon: "questionmark.circle.fill")
            }
            HStack(spacing: 10) {
                LoginMiniStat(value: "\(vm.credentials.count)", label: "Total", color: .blue, icon: "person.2.fill")
            }
        }
    }

    private func credentialSection(title: String, creds: [LoginCredential], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(color)
                Text(title).font(.headline)
                Spacer()
                Text("\(creds.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(color.opacity(0.12)).clipShape(Capsule()).foregroundStyle(color)
            }
            ForEach(creds) { cred in
                LoginCredentialRow(credential: cred, accentColor: color)
            }
        }
    }

    private var noAccSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(.red)
                Text("No Account").font(.headline)
                Spacer()
                Text("\(vm.noAccCredentials.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.red.opacity(0.12)).clipShape(Capsule()).foregroundStyle(.red)
                Button { vm.purgeNoAccCredentials() } label: {
                    Text("Purge All").font(.caption.bold()).foregroundStyle(.red)
                }
            }
            ForEach(vm.noAccCredentials) { cred in
                LoginCredentialRow(credential: cred, accentColor: .red)
            }
        }
    }

    private var permDisabledSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.slash.fill").font(.subheadline).foregroundStyle(.red.opacity(0.7))
                Text("Perm Disabled").font(.headline)
                Spacer()
                Text("\(vm.permDisabledCredentials.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.red.opacity(0.08)).clipShape(Capsule()).foregroundStyle(.red.opacity(0.7))
                Button { vm.purgePermDisabledCredentials() } label: {
                    Text("Purge").font(.caption.bold()).foregroundStyle(.red.opacity(0.7))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.red.opacity(0.7))
                Text("Permanently disabled/blacklisted. Excluded from queue.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.04)).clipShape(.rect(cornerRadius: 8))
            ForEach(vm.permDisabledCredentials) { cred in
                LoginCredentialRow(credential: cred, accentColor: .red.opacity(0.7))
            }
        }
    }

    private var tempDisabledSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark").font(.subheadline).foregroundStyle(.orange)
                Text("Temp Disabled").font(.headline)
                Spacer()
                Text("\(vm.tempDisabledCredentials.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12)).clipShape(Capsule()).foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption2).foregroundStyle(.orange)
                Text("Temporarily locked. Assign passwords in Temp Disabled tab.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.06)).clipShape(.rect(cornerRadius: 8))
            ForEach(vm.tempDisabledCredentials) { cred in
                LoginCredentialRow(credential: cred, accentColor: .orange)
            }
        }
    }

    private var unsureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill").font(.subheadline).foregroundStyle(.yellow)
                Text("Unsure").font(.headline)
                Spacer()
                Text("\(vm.unsureCredentials.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.12)).clipShape(Capsule()).foregroundStyle(.yellow)
                Button { vm.purgeUnsureCredentials() } label: {
                    Text("Purge").font(.caption.bold()).foregroundStyle(.yellow)
                }
            }
            ForEach(vm.unsureCredentials) { cred in
                LoginCredentialRow(credential: cred, accentColor: .yellow)
            }
        }
    }

    private var dashboardActionButtons: some View {
        HStack(spacing: 10) {
            Button {
                vm.testAllUntested()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Test All Untested")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(vm.isRunning ? accentColor.opacity(0.3) : accentColor)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(vm.isRunning || vm.untestedCredentials.isEmpty)

            Button {
                vm.testAllUntested()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                    Text("Select Testing")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill))
                .foregroundStyle(.primary)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("No Credentials Added").font(.title3.bold())
            Text("Go to Credentials tab to import.\nSupports email:password format.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}

struct LoginMiniStat: View {
    let value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.system(.title3, design: .monospaced, weight: .bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct LoginCredentialRow: View {
    let credential: LoginCredential
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(accentColor.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: "person.fill").font(.title3).foregroundStyle(accentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(credential.username)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 8) {
                    Text(credential.maskedPassword)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    if credential.totalTests > 0 {
                        Text("\(credential.successCount)/\(credential.totalTests) passed")
                            .font(.caption2)
                            .foregroundStyle(credential.status == .working ? .green : .red)
                    }
                }
            }
            Spacer()
            if credential.status == .testing {
                ProgressView().tint(.green)
            } else {
                HStack(spacing: 3) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(credential.status.rawValue).font(.system(.caption2, design: .monospaced)).foregroundStyle(statusColor)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch credential.status {
        case .working: .green
        case .noAcc: .red
        case .permDisabled: .red.opacity(0.7)
        case .tempDisabled: .orange
        case .unsure: .yellow
        case .testing: .green
        case .untested: .secondary
        }
    }
}

// MARK: - Credentials List

struct LoginCredentialsListView: View {
    let vm: LoginViewModel
    @State private var showImportSheet: Bool = false
    @State private var importText: String = ""
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .dateAdded
    @State private var sortAscending: Bool = false
    @State private var filterStatus: CredentialStatus? = nil
    @State private var bulkText: String = ""
    @State private var showBulkImport: Bool = false
    @State private var bulkImportResult: String? = nil
    @State private var viewMode: ViewMode = .list

    nonisolated enum SortOption: String, CaseIterable, Identifiable, Sendable {
        case dateAdded = "Date Added"
        case lastTest = "Last Test"
        case successRate = "Success Rate"
        case totalTests = "Total Tests"
        case username = "Username"
        var id: String { rawValue }
    }

    private var filteredCredentials: [LoginCredential] {
        var result = vm.credentials
        if !searchText.isEmpty {
            result = result.filter {
                $0.username.localizedStandardContains(searchText) ||
                $0.notes.localizedStandardContains(searchText)
            }
        }
        if let status = filterStatus { result = result.filter { $0.status == status } }

        result.sort { a, b in
            let comparison: Bool
            switch sortOption {
            case .dateAdded: comparison = a.addedAt > b.addedAt
            case .lastTest: comparison = (a.lastTestedAt ?? .distantPast) > (b.lastTestedAt ?? .distantPast)
            case .successRate: comparison = a.successRate > b.successRate
            case .totalTests: comparison = a.totalTests > b.totalTests
            case .username: comparison = a.username < b.username
            }
            return sortAscending ? !comparison : comparison
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            sortFilterBar
            if showBulkImport { bulkImportBox }
            if viewMode == .tile {
                credentialsTileGrid
            } else {
                credentialsList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Credentials")
        .searchable(text: $searchText, prompt: "Search credentials...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ViewModeToggle(mode: $viewMode, accentColor: .green)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { showBulkImport.toggle() }
                } label: {
                    Image(systemName: showBulkImport ? "rectangle.and.pencil.and.ellipsis" : "doc.on.clipboard")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImportSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showImportSheet) { importSheet }
    }

    private var bulkImportBox: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Bulk Import", systemImage: "doc.on.clipboard.fill")
                    .font(.subheadline.bold())
                Spacer()
                if let result = bulkImportResult {
                    Text(result)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                Button { withAnimation(.snappy) { showBulkImport = false; bulkText = ""; bulkImportResult = nil } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(["user:pass", "user;pass", "user,pass"], id: \.self) { fmt in
                    Text(fmt)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .foregroundStyle(.secondary)

            TextEditor(text: $bulkText)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
                .frame(height: 120)
                .overlay(alignment: .topLeading) {
                    if bulkText.isEmpty {
                        Text("Paste credentials here...\nOne per line: user:pass")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 14).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 12) {
                let lineCount = bulkText.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                if lineCount > 0 {
                    Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let clipboardString = UIPasteboard.general.string, !clipboardString.isEmpty {
                        bulkText = clipboardString
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button {
                    let before = vm.credentials.count
                    vm.smartImportCredentials(bulkText)
                    let added = vm.credentials.count - before
                    withAnimation(.snappy) {
                        bulkImportResult = "\(added) added"
                    }
                    bulkText = ""
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.snappy) { bulkImportResult = nil }
                    }
                } label: {
                    Label("Import", systemImage: "arrow.down.doc.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var sortFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(SortOption.allCases) { option in
                        Button {
                            withAnimation(.snappy) {
                                if sortOption == option { sortAscending.toggle() }
                                else { sortOption = option; sortAscending = false }
                            }
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option { Image(systemName: sortAscending ? "chevron.up" : "chevron.down") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down").font(.caption2)
                        Text(sortOption.rawValue).font(.subheadline.weight(.medium))
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.green.opacity(0.15)).foregroundStyle(.green).clipShape(Capsule())
                }

                Text("\(filteredCredentials.count) credentials")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill)).clipShape(Capsule())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        LoginFilterChip(title: "All", isSelected: filterStatus == nil) { withAnimation(.snappy) { filterStatus = nil } }
                        LoginFilterChip(title: "Working", isSelected: filterStatus == .working) { withAnimation(.snappy) { filterStatus = .working } }
                        LoginFilterChip(title: "Untested", isSelected: filterStatus == .untested) { withAnimation(.snappy) { filterStatus = .untested } }
                        LoginFilterChip(title: "No Acc", isSelected: filterStatus == .noAcc) { withAnimation(.snappy) { filterStatus = .noAcc } }
                        LoginFilterChip(title: "Perm Dis", isSelected: filterStatus == .permDisabled) { withAnimation(.snappy) { filterStatus = .permDisabled } }
                        LoginFilterChip(title: "Temp Dis", isSelected: filterStatus == .tempDisabled) { withAnimation(.snappy) { filterStatus = .tempDisabled } }
                        LoginFilterChip(title: "Unsure", isSelected: filterStatus == .unsure) { withAnimation(.snappy) { filterStatus = .unsure } }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
    }

    private var credentialsList: some View {
        Group {
            if filteredCredentials.isEmpty {
                ContentUnavailableView {
                    Label("No Credentials", systemImage: "person.badge.key")
                } description: {
                    if vm.credentials.isEmpty { Text("Import credentials to get started.") }
                    else { Text("No credentials match your filters.") }
                } actions: {
                    if vm.credentials.isEmpty { Button("Import Credentials") { showImportSheet = true } }
                }
            } else {
                List {
                    ForEach(filteredCredentials) { cred in
                        NavigationLink(value: cred.id) {
                            LoginSavedCredRow(credential: cred)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { vm.deleteCredential(cred) } label: { Label("Delete", systemImage: "trash") }
                            Button { vm.testSingleCredential(cred) } label: { Label("Test", systemImage: "play.fill") }.tint(.green)
                        }
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var credentialsTileGrid: some View {
        Group {
            if filteredCredentials.isEmpty {
                ContentUnavailableView {
                    Label("No Credentials", systemImage: "person.badge.key")
                } description: {
                    if vm.credentials.isEmpty { Text("Import credentials to get started.") }
                    else { Text("No credentials match your filters.") }
                } actions: {
                    if vm.credentials.isEmpty { Button("Import Credentials") { showImportSheet = true } }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(filteredCredentials) { cred in
                            NavigationLink(value: cred.id) {
                                let screenshot = vm.screenshotsForCredential(cred.id).first?.image
                                ScreenshotTileView(
                                    screenshot: screenshot,
                                    title: cred.username,
                                    subtitle: cred.maskedPassword,
                                    statusColor: credTileStatusColor(cred.status),
                                    statusText: cred.status.rawValue,
                                    badge: cred.totalTests > 0 ? "\(cred.successCount)/\(cred.totalTests)" : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func credTileStatusColor(_ status: CredentialStatus) -> Color {
        switch status {
        case .working: .green
        case .noAcc: .red
        case .permDisabled: .red.opacity(0.7)
        case .tempDisabled: .orange
        case .unsure: .yellow
        case .testing: .green
        case .untested: .secondary
        }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Smart Import").font(.headline)
                    Text("Paste login credentials in common formats. One per line.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Supported formats:").font(.caption.bold()).foregroundStyle(.secondary)
                        Group {
                            Text("user@email.com:password123")
                            Text("user@email.com;password123")
                            Text("user@email.com,password123")
                            Text("user@email.com|password123")
                        }
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 180)
                Spacer()
            }
            .padding()
            .navigationTitle("Import Credentials").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showImportSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        vm.smartImportCredentials(importText)
                        importText = ""
                        showImportSheet = false
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}

struct LoginSavedCredRow: View {
    let credential: LoginCredential

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(statusColor.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "person.fill").font(.title3.bold()).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(credential.username)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(credential.maskedPassword)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    if credential.totalTests > 0 {
                        Text("\(credential.successCount)/\(credential.totalTests)")
                            .font(.caption2.bold())
                            .foregroundStyle(credential.lastTestSuccess == true ? .green : .red)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 3) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(credential.status.rawValue)
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(statusColor)
                }
                if credential.status == .testing { ProgressView().controlSize(.small).tint(.green) }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch credential.status {
        case .working: .green
        case .noAcc: .red
        case .permDisabled: .red.opacity(0.7)
        case .tempDisabled: .orange
        case .unsure: .yellow
        case .testing: .green
        case .untested: .secondary
        }
    }
}

struct LoginFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isSelected ? Color.green : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Credential Detail

struct LoginCredentialDetailView: View {
    let credential: LoginCredential
    let vm: LoginViewModel
    @State private var showCopiedToast: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                credentialHeader
                statsSection
                actionsSection
                if !credential.testResults.isEmpty { testHistorySection }
                infoSection
            }
            .listStyle(.insetGrouped)

            if showCopiedToast {
                Text("Copied to clipboard")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.green.gradient, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
        .navigationTitle(credential.username).navigationBarTitleDisplayMode(.inline)
    }

    private var credentialHeader: some View {
        Section {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [statusGradientColor, statusGradientColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 160)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "person.badge.key.fill").font(.title).foregroundStyle(.white)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(statusBadgeColor).frame(width: 6, height: 6)
                                Text(credential.status.rawValue).font(.caption2.bold())
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial).clipShape(Capsule())
                        }

                        Text(credential.username)
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PASSWORD").font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                                Text(credential.maskedPassword)
                                    .font(.system(.subheadline, design: .monospaced, weight: .medium)).foregroundStyle(.white)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("TESTS").font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                                Text("\(credential.totalTests)")
                                    .font(.system(.subheadline, design: .monospaced, weight: .medium)).foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    private var statusGradientColor: Color {
        switch credential.status {
        case .working: .green
        case .noAcc: .red
        case .permDisabled: .red.opacity(0.7)
        case .tempDisabled: .orange
        case .unsure: .yellow
        case .testing: .teal
        case .untested: .gray
        }
    }

    private var statusBadgeColor: Color {
        switch credential.status {
        case .working: .green
        case .noAcc: .red
        case .permDisabled: .red.opacity(0.7)
        case .tempDisabled: .orange
        case .unsure: .yellow
        case .testing: .green
        case .untested: .secondary
        }
    }

    private var statsSection: some View {
        Section("Performance") {
            HStack {
                StatItem(value: "\(credential.totalTests)", label: "Total Tests", color: .blue)
                StatItem(value: "\(credential.successCount)", label: "Passed", color: .green)
                StatItem(value: "\(credential.failureCount)", label: "Failed", color: .red)
            }
            if credential.totalTests > 0 {
                LabeledContent("Success Rate") {
                    Text(String(format: "%.0f%%", credential.successRate * 100))
                        .font(.system(.body, design: .monospaced, weight: .bold))
                        .foregroundStyle(credential.successRate >= 0.5 ? .green : .red)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                vm.testSingleCredential(credential)
            } label: {
                HStack { Spacer(); Label("Run Login Test", systemImage: "play.fill").font(.headline); Spacer() }
            }
            .disabled(credential.status == .testing)
            .listRowBackground(credential.status == .testing ? Color.green.opacity(0.3) : Color.green)
            .foregroundStyle(.white)

            Button {
                UIPasteboard.general.string = credential.exportFormat
                withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
                Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopiedToast = false } }
            } label: { Label("Copy Credential", systemImage: "doc.on.doc") }

            if credential.status == .noAcc || credential.status == .permDisabled || credential.status == .tempDisabled || credential.status == .unsure {
                Button { vm.restoreCredential(credential) } label: { Label("Restore to Untested", systemImage: "arrow.counterclockwise") }
                Button(role: .destructive) { vm.deleteCredential(credential) } label: { Label("Delete Permanently", systemImage: "trash") }
            }
        }
    }

    private var testHistorySection: some View {
        Section("Test History") {
            ForEach(credential.testResults) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red).font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(result.success ? "Success" : "Failed").font(.subheadline.bold()).foregroundStyle(result.success ? .green : .red)
                            Text(result.formattedDuration).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text(result.formattedDate).font(.caption).foregroundStyle(.tertiary)
                        if let err = result.errorMessage {
                            Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                        }
                        if let detail = result.responseDetail {
                            Text(detail).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var infoSection: some View {
        Section("Credential Info") {
            LabeledContent("Username") { Text(credential.username).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
            LabeledContent("Password") { Text(credential.password).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
            LabeledContent("Export Format") { Text(credential.exportFormat).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary) }
            LabeledContent("Added") { Text(credential.addedAt, style: .date) }
            if let lastTest = credential.lastTestedAt {
                LabeledContent("Last Tested") { Text(lastTest, style: .relative).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Working List

struct LoginWorkingListView: View {
    let vm: LoginViewModel
    @State private var showCopiedToast: Bool = false
    @State private var showFileExporter: Bool = false
    @State private var exportDocument: CardExportDocument?
    @State private var viewMode: ViewMode = .list
    @State private var selectedCredential: LoginCredential?

    var body: some View {
        VStack(spacing: 0) {
            if vm.workingCredentials.isEmpty {
                ContentUnavailableView("No Working Logins", systemImage: "checkmark.shield", description: Text("Credentials that pass login tests will appear here."))
            } else {
                exportBar
                if viewMode == .tile {
                    workingTileGrid
                } else {
                    credentialsList
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Working Logins")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ViewModeToggle(mode: $viewMode, accentColor: .green)
            }
            if !vm.workingCredentials.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { copyAllCredentials() } label: { Label("Copy All", systemImage: "doc.on.doc") }
                        Button { exportAsTxt() } label: { Label("Export as .txt", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("Copied to clipboard")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.green.gradient, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
        .fileExporter(isPresented: $showFileExporter, document: exportDocument, contentType: .plainText, defaultFilename: "working_logins_\(dateStamp()).txt") { result in
            switch result {
            case .success: vm.log("Exported \(vm.workingCredentials.count) working credentials to file", level: .success)
            case .failure(let error): vm.log("Export failed: \(error.localizedDescription)", level: .error)
            }
        }
        .sheet(item: $selectedCredential) { cred in
            NavigationStack {
                LoginCredentialDetailView(credential: cred, vm: vm)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var exportBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            Text("\(vm.workingCredentials.count) working logins").font(.subheadline.bold())
            Spacer()
            Button { copyAllCredentials() } label: {
                Label("Copy All", systemImage: "doc.on.doc")
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.green.opacity(0.15)).foregroundStyle(.green).clipShape(Capsule())
            }
        }
        .padding(.horizontal).padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var credentialsList: some View {
        List {
            ForEach(vm.workingCredentials) { cred in
                let latestScreenshot = vm.screenshotsForCredential(cred.id).first?.image
                LoginWorkingRow(credential: cred, onCopy: { copyCredential(cred) }, screenshot: latestScreenshot)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { copyCredential(cred) } label: { Label("Copy", systemImage: "doc.on.doc") }.tint(.green)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { vm.retestCredential(cred) } label: { Label("Retest", systemImage: "arrow.clockwise") }.tint(.blue)
                    }
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
    }

    private var workingTileGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(vm.workingCredentials) { cred in
                    let latestScreenshot = vm.screenshotsForCredential(cred.id).first?.image
                    Button { selectedCredential = cred } label: {
                        ScreenshotTileView(
                            screenshot: latestScreenshot,
                            title: cred.username,
                            subtitle: cred.maskedPassword,
                            statusColor: .green,
                            statusText: "Working",
                            badge: cred.totalTests > 0 ? "\(cred.successCount)/\(cred.totalTests)" : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { copyCredential(cred) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button { vm.retestCredential(cred) } label: { Label("Retest", systemImage: "arrow.clockwise") }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private func copyCredential(_ cred: LoginCredential) {
        UIPasteboard.general.string = cred.exportFormat
        withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopiedToast = false } }
    }

    private func copyAllCredentials() {
        let text = vm.exportWorkingCredentials()
        UIPasteboard.general.string = text
        vm.log("Copied \(vm.workingCredentials.count) working credentials to clipboard", level: .success)
        withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopiedToast = false } }
    }

    private func exportAsTxt() {
        let text = vm.exportWorkingCredentials()
        exportDocument = CardExportDocument(text: text)
        showFileExporter = true
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }
}

struct LoginWorkingRow: View {
    let credential: LoginCredential
    let onCopy: () -> Void
    var screenshot: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let screenshot {
                Color.clear.frame(width: 40, height: 40)
                    .overlay { Image(uiImage: screenshot).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false) }
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: "person.fill.checkmark").font(.title3.bold()).foregroundStyle(.green)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(credential.username)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(credential.maskedPassword)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    if credential.totalTests > 0 {
                        Text("\(credential.successCount)/\(credential.totalTests)")
                            .font(.caption2.bold()).foregroundStyle(.green)
                    }
                }
            }
            Spacer()
            Button { onCopy() } label: {
                Image(systemName: "doc.on.doc").font(.subheadline).foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Session Monitor

struct LoginSessionMonitorContentView: View {
    let vm: LoginViewModel
    @State private var selectedAttempt: LoginAttempt?
    @State private var filterStatus: FilterOption = .all
    @State private var viewMode: ViewMode = .list

    nonisolated enum FilterOption: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case active = "Active"
        case completed = "Passed"
        case failed = "Failed"
        var id: String { rawValue }
    }

    private var filteredAttempts: [LoginAttempt] {
        switch filterStatus {
        case .all: vm.attempts
        case .active: vm.attempts.filter { !$0.status.isTerminal }
        case .completed: vm.completedAttempts
        case .failed: vm.failedAttempts
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if filteredAttempts.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "rectangle.stack", description: Text("Test credentials to see sessions here."))
            } else if viewMode == .tile {
                sessionTileGrid
            } else {
                sessionListView
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ViewModeToggle(mode: $viewMode, accentColor: .green)
            }
        }
        .sheet(item: $selectedAttempt) { attempt in
            LoginSessionDetailSheet(attempt: attempt)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterOption.allCases) { option in
                    LoginSessionFilterChip(title: option.rawValue, count: countFor(option), isSelected: filterStatus == option) {
                        withAnimation(.snappy) { filterStatus = option }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
    }

    private func countFor(_ option: FilterOption) -> Int {
        switch option {
        case .all: vm.attempts.count
        case .active: vm.activeAttempts.count
        case .completed: vm.completedAttempts.count
        case .failed: vm.failedAttempts.count
        }
    }

    private var sessionListView: some View {
        List(filteredAttempts) { attempt in
            Button { selectedAttempt = attempt } label: { LoginSessionRow(attempt: attempt) }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
        }
        .listStyle(.insetGrouped)
    }

    private var sessionTileGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(filteredAttempts) { attempt in
                    Button { selectedAttempt = attempt } label: {
                        let latestScreenshot = attempt.responseSnapshot ?? vm.screenshotsForAttempt(attempt).first?.image
                        ScreenshotTileView(
                            screenshot: latestScreenshot,
                            title: attempt.credential.username,
                            subtitle: "S\(attempt.sessionIndex) · \(attempt.formattedDuration)",
                            statusColor: attemptStatusColor(attempt.status),
                            statusText: attempt.status.rawValue,
                            badge: attempt.hasScreenshot ? "📷" : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private func attemptStatusColor(_ status: LoginAttemptStatus) -> Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .queued: .secondary
        default: .green
        }
    }
}

struct LoginSessionFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                if count > 0 {
                    Text("\(count)").font(.system(.caption2, design: .monospaced, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.25) : Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(isSelected ? Color.green : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LoginSessionRow: View {
    let attempt: LoginAttempt

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let snapshot = attempt.responseSnapshot {
                    Color.clear.frame(width: 48, height: 48)
                        .overlay { Image(uiImage: snapshot).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false) }
                        .clipShape(.rect(cornerRadius: 6))
                } else {
                    Image(systemName: attempt.status.icon)
                        .foregroundStyle(statusColor)
                        .symbolEffect(.pulse, isActive: !attempt.status.isTerminal)
                        .frame(width: 48, height: 48)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(attempt.credential.username)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    if let snippet = attempt.responseSnippet {
                        Text(snippet.prefix(60))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary).lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("S\(attempt.sessionIndex)")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(.rect(cornerRadius: 4)).foregroundStyle(.primary)
                    if attempt.hasScreenshot {
                        Image(systemName: "camera.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if !attempt.status.isTerminal {
                ProgressView(value: attempt.status.progress).tint(.green)
            }

            HStack {
                Text(attempt.status.rawValue).font(.caption).foregroundStyle(statusColor)
                Spacer()
                Label(attempt.formattedDuration, systemImage: "timer")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch attempt.status {
        case .completed: .green
        case .failed: .red
        case .queued: .secondary
        default: .green
        }
    }
}

struct LoginSessionDetailSheet: View {
    let attempt: LoginAttempt
    @State private var showFullScreenshot: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = attempt.responseSnapshot {
                    Section("Screenshot") {
                        Button { showFullScreenshot = true } label: {
                            Image(uiImage: snapshot)
                                .resizable().aspectRatio(contentMode: .fit)
                                .clipShape(.rect(cornerRadius: 8))
                                .frame(maxHeight: 200)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("Details") {
                    LabeledContent("Username") {
                        Text(attempt.credential.username).font(.system(.caption, design: .monospaced))
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 4) {
                            Image(systemName: attempt.status.icon)
                            Text(attempt.status.rawValue)
                        }
                        .foregroundStyle(attempt.status == .completed ? .green : attempt.status == .failed ? .red : .blue)
                    }
                    LabeledContent("Session", value: "S\(attempt.sessionIndex)")
                    LabeledContent("Duration", value: attempt.formattedDuration)
                    if let url = attempt.detectedURL {
                        LabeledContent("Final URL") {
                            Text(url).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }

                if let error = attempt.errorMessage {
                    Section("Error") {
                        Text(error).font(.system(.body, design: .monospaced)).foregroundStyle(.red)
                    }
                }

                if let snippet = attempt.responseSnippet {
                    Section("Response Preview") {
                        Text(snippet)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                }

                Section("Execution Log") {
                    if attempt.logs.isEmpty {
                        Text("No log entries").foregroundStyle(.secondary)
                    } else {
                        ForEach(attempt.logs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTime).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 80, alignment: .leading)
                                Text(entry.level.rawValue).font(.system(.caption2, design: .monospaced, weight: .bold))
                                    .foregroundStyle(logColor(entry.level)).frame(width: 36)
                                Text(entry.message).font(.system(.caption, design: .monospaced)).foregroundStyle(.primary)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Session Detail").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showFullScreenshot) {
                if let snapshot = attempt.responseSnapshot {
                    FullScreenshotView(image: snapshot)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func logColor(_ level: PPSRLogEntry.Level) -> Color {
        switch level { case .info: .blue; case .success: .green; case .warning: .orange; case .error: .red }
    }
}

struct FullScreenshotView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .background(.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Settings

struct LoginSettingsContentView: View {
    @Bindable var vm: LoginViewModel
    @State private var showDebugScreenshots: Bool = false
    @AppStorage("introVideoEnabled") private var introVideoEnabled: Bool = false

    private var accentColor: Color {
        vm.isIgnitionMode ? .orange : .green
    }

    var body: some View {
        List {
            siteToggleSection
            quickActionsSection
            blacklistSection
            stealthSection
            concurrencySection
            debugSection
            appearanceSection
            introVideoSection
            iCloudSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced Settings")
        .sheet(isPresented: $showDebugScreenshots) {
            NavigationStack {
                LoginDebugScreenshotsView(vm: vm)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showDebugScreenshots = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private var siteToggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { vm.dualSiteMode },
                set: { newVal in
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        if newVal {
                            vm.setSiteMode(.dual)
                        } else {
                            vm.setSiteMode(vm.isIgnitionMode ? .ignition : .joe)
                        }
                    }
                }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dual Mode").font(.body)
                        Text("Test Joe + Ignition simultaneously").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.cyan)
            .sensoryFeedback(.impact(weight: .medium), trigger: vm.dualSiteMode)
        } header: {
            Text("Site Mode")
        } footer: {
            if vm.dualSiteMode {
                Text("Dual mode — half sessions test Joe Fortune, half test Ignition simultaneously.")
            } else {
                Text("\(vm.isIgnitionMode ? "Ignition" : "Joe") mode — URLs rotate through \(vm.isIgnitionMode ? "Ignition" : "Joe Fortune") domains.")
            }
        }
    }

    private var quickActionsSection: some View {
        Section {
            if !vm.untestedCredentials.isEmpty {
                Button {
                    vm.testAllUntested()
                } label: {
                    HStack { Spacer(); Label("Test All Untested (\(vm.untestedCredentials.count))", systemImage: "play.fill").font(.headline); Spacer() }
                }
                .disabled(vm.isRunning)
                .listRowBackground(vm.isRunning ? accentColor.opacity(0.4) : accentColor)
                .foregroundStyle(.white)
                .sensoryFeedback(.impact(weight: .heavy), trigger: vm.isRunning)
            }

            Button {
                vm.testAllUntested()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist").foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select Testing").font(.body)
                        Text("Choose specific credentials to test").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Quick Actions")
        }
    }

    private var stealthSection: some View {
        Section {
            Toggle(isOn: $vm.stealthEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill").foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ultra Stealth Mode").font(.body)
                        Text("Rotating user agents, fingerprints & viewports").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.purple)
            .sensoryFeedback(.impact(weight: .light), trigger: vm.stealthEnabled)
        } header: {
            Text("Stealth")
        } footer: {
            Text(vm.stealthEnabled ? "Each session uses a unique browser identity. Complete history wipe between tests." : "Enable to rotate browser fingerprints across sessions.")
        }
    }

    private var introVideoSection: some View {
        Section {
            Toggle(isOn: $introVideoEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "film.fill").foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Intro Video").font(.body)
                        Text("Play intro video on app launch").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.pink)
        } header: {
            Text("Startup")
        }
    }

    private var concurrencySection: some View {
        Section {
            Picker("Max Sessions", selection: $vm.maxConcurrency) {
                ForEach(1...8, id: \.self) { n in Text("\(n)").tag(n) }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Test Timeout")
                Spacer()
                Picker("Timeout", selection: Binding(
                    get: { Int(vm.testTimeout) },
                    set: { vm.testTimeout = TimeInterval($0) }
                )) {
                    Text("30s").tag(30)
                    Text("45s").tag(45)
                    Text("60s").tag(60)
                    Text("90s").tag(90)
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Concurrency")
        } footer: {
            Text("Up to 8 concurrent WKWebView sessions. Timeout per test: \(Int(vm.testTimeout))s.")
        }
    }

    private var debugSection: some View {
        Section {
            Toggle(isOn: $vm.debugMode) {
                HStack(spacing: 10) {
                    Image(systemName: "ladybug.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debug Mode").font(.body)
                        Text("Captures screenshots + detailed evaluation per test").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.orange)

            if vm.debugMode {
                Button { showDebugScreenshots = true } label: {
                    HStack {
                        Image(systemName: "photo.stack").foregroundStyle(.orange)
                        Text("Debug Screenshots").foregroundStyle(.primary)
                        Spacer()
                        Text("\(vm.debugScreenshots.count)").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }

                if !vm.debugScreenshots.isEmpty {
                    let passCount = vm.debugScreenshots.filter({ $0.effectiveResult == .markedPass }).count
                    let failCount = vm.debugScreenshots.filter({ $0.effectiveResult == .markedFail }).count
                    let unknownCount = vm.debugScreenshots.filter({ $0.effectiveResult == .none }).count
                    HStack(spacing: 12) {
                        if passCount > 0 {
                            Label("\(passCount) pass", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(.green)
                        }
                        if failCount > 0 {
                            Label("\(failCount) fail", systemImage: "xmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(.red)
                        }
                        if unknownCount > 0 {
                            Label("\(unknownCount) uncertain", systemImage: "questionmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        }
                        Spacer()
                    }

                    Button(role: .destructive) { vm.clearDebugScreenshots() } label: { Label("Clear All Screenshots", systemImage: "trash") }
                }
            }
        } header: {
            Text("Debug")
        } footer: {
            if vm.debugMode {
                Text("Screenshots are always captured for session previews. Debug mode adds them to the Debug tab for review and correction.")
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $vm.appearanceMode) {
                ForEach(LoginViewModel.AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            } label: {
                HStack(spacing: 10) { Image(systemName: "paintbrush.fill").foregroundStyle(.purple); Text("Appearance") }
            }

            if vm.isIgnitionMode {
                HStack(spacing: 10) {
                    Image(systemName: "moon.fill").foregroundStyle(.orange)
                    Text("Ignition Dark Mode")
                    Spacer()
                    Text("Active").font(.caption.bold()).foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12)).clipShape(Capsule())
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            if vm.isIgnitionMode {
                Text("Dark mode is forced while in Ignition mode.")
            }
        }
    }

    private var iCloudSection: some View {
        Section {
            Button { vm.syncFromiCloud() } label: {
                HStack(spacing: 10) { Image(systemName: "icloud.and.arrow.down").foregroundStyle(.blue); Text("Sync from iCloud") }
            }
            Button {
                vm.persistCredentials()
                vm.log("Forced save to local + iCloud", level: .success)
            } label: {
                HStack(spacing: 10) { Image(systemName: "icloud.and.arrow.up").foregroundStyle(.blue); Text("Force Save to iCloud") }
            }
        } header: {
            Text("iCloud Sync")
        }
    }

    private var blacklistSection: some View {
        Section {
            Toggle(isOn: Bindable(vm.blacklistService).autoExcludeBlacklist) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.slash.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Exclude Blacklist").font(.body)
                        Text("Skip blacklisted accounts during import").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.red)

            Toggle(isOn: Bindable(vm.blacklistService).autoBlacklistNoAcc) {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Blacklist No Account").font(.body)
                        Text("Add no-acc results to blacklist automatically").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.orange)

            HStack(spacing: 10) {
                Image(systemName: "hand.raised.slash.fill").foregroundStyle(.red)
                Text("Blacklisted")
                Spacer()
                Text("\(vm.blacklistService.blacklistedEmails.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(.secondary)
            }
        } header: {
            Text("Blacklist")
        } footer: {
            Text("Blacklisted emails are excluded from import queues. Manage the full blacklist in the More tab.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "8.0.0")
            LabeledContent("Engine", value: "WKWebView Live")
            LabeledContent("Storage", value: "Local + iCloud")
            LabeledContent("Stealth") { Text(vm.stealthEnabled ? "Ultra Stealth" : "Standard").foregroundStyle(vm.stealthEnabled ? .purple : .secondary) }
            LabeledContent("Mode") {
                HStack(spacing: 6) {
                    Text(vm.isIgnitionMode ? "Ignition" : "Joe Fortune")
                        .foregroundStyle(vm.isIgnitionMode ? .orange : .green)
                    if vm.dualSiteMode {
                        Text("DUAL").font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.cyan).padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.12)).clipShape(Capsule())
                    }
                }
            }
            LabeledContent("Session Wipe") { Text("Full — cookies, cache, storage").foregroundStyle(.cyan) }
            Button(role: .destructive) { vm.clearAll() } label: { Label("Clear Session History", systemImage: "trash") }
        } header: {
            Text("About")
        }
    }

}

// MARK: - More Menu

struct LoginMoreMenuView: View {
    let vm: LoginViewModel
    @State private var showExportSheet: Bool = false
    @State private var exportDocument: CardExportDocument?
    @State private var showFileExporter: Bool = false
    @State private var showCopiedToast: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var importConfigText: String = ""
    @State private var importResult: AppDataExportService.ImportResult?
    @State private var showImportFileImporter: Bool = false
    @State private var showImportFilePicker: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Section {
                    NavigationLink {
                        LoginNetworkSettingsView(vm: vm)
                    } label: {
                        moreRow(icon: "network", title: "Networks", subtitle: "URLs, proxies, VPN, DNS & connectivity", color: .blue)
                    }

                    NavigationLink {
                        LoginSettingsContentView(vm: vm)
                    } label: {
                        moreRow(icon: "gearshape.fill", title: "Advanced Settings", subtitle: "Automation, stealth, debug & more", color: .secondary)
                    }
                }

                Section("Flow Recorder") {
                    NavigationLink {
                        FlowRecorderView()
                    } label: {
                        moreRow(icon: "record.circle", title: "Record Login Flow", subtitle: "Record & replay human login patterns", color: .red)
                    }

                    NavigationLink {
                        SavedFlowsView(vm: FlowRecorderViewModel())
                    } label: {
                        let flowCount = FlowPersistenceService.shared.loadFlows().count
                        HStack(spacing: 12) {
                            Image(systemName: "tray.full.fill").font(.title3).foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Saved Flows").font(.subheadline.bold())
                                Text("\(flowCount) recorded login patterns").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Account Tools") {
                    NavigationLink {
                        CheckDisabledAccountsView(vm: vm)
                    } label: {
                        moreRow(icon: "magnifyingglass.circle.fill", title: "Check Disabled Accounts", subtitle: "Fast forgot-password check", color: .orange)
                    }

                    NavigationLink {
                        TempDisabledAccountsView(vm: vm)
                    } label: {
                        moreRow(icon: "clock.badge.exclamationmark", title: "Temp Disabled Accounts", subtitle: "\(vm.tempDisabledCredentials.count) accounts", color: .orange)
                    }
                }

                Section("Data") {
                    NavigationLink {
                        BlacklistView(vm: vm)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.slash.fill")
                                .font(.title3).foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Blacklist").font(.subheadline.bold())
                                Text("\(vm.blacklistService.blacklistedEmails.count) blacklisted").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vm.blacklistService.autoExcludeBlacklist {
                                Text("AUTO")
                                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.red.opacity(0.12)).clipShape(Capsule())
                            }
                        }
                    }

                    NavigationLink {
                        CredentialExportView(vm: vm)
                    } label: {
                        moreRow(icon: "square.and.arrow.up.fill", title: "Export Credentials", subtitle: "Text or CSV by category", color: .blue)
                    }
                }

                Section("Comprehensive Export") {
                    Button {
                        let text = AppDataExportService.shared.exportComprehensiveState()
                        UIPasteboard.general.string = text
                        vm.log("Copied comprehensive state to clipboard", level: .success)
                        withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
                        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopiedToast = false } }
                    } label: {
                        moreRow(icon: "doc.text.fill", title: "Export Full State", subtitle: "URLs, proxies, DNS, VPN, blacklist, settings", color: .indigo)
                    }

                    Button {
                        let text = AppDataExportService.shared.exportTestingHistory(credentials: vm.credentials)
                        UIPasteboard.general.string = text
                        vm.log("Copied testing history to clipboard", level: .success)
                        withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
                        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopiedToast = false } }
                    } label: {
                        moreRow(icon: "clock.arrow.circlepath", title: "Export Testing History", subtitle: "All credential test results", color: .purple)
                    }

                    Button {
                        let text = AppDataExportService.shared.exportURLHistory()
                        UIPasteboard.general.string = text
                        vm.log("Copied URL history to clipboard", level: .success)
                        withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
                        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopiedToast = false } }
                    } label: {
                        moreRow(icon: "link.circle.fill", title: "Export URL Performance", subtitle: "Success rates, response times", color: .cyan)
                    }

                    Button {
                        let text = AppDataExportService.shared.exportComprehensiveState()
                        exportDocument = CardExportDocument(text: text)
                        showFileExporter = true
                    } label: {
                        moreRow(icon: "square.and.arrow.up.fill", title: "Export All to File", subtitle: "Save complete state as .txt", color: .blue)
                    }

                    Button {
                        let json = AppDataExportService.shared.exportJSON()
                        exportDocument = CardExportDocument(text: json)
                        showFileExporter = true
                    } label: {
                        moreRow(icon: "doc.badge.arrow.up.fill", title: "Export JSON Config", subtitle: "Restorable JSON backup of all configs", color: .teal)
                    }
                }

                Section("Import & Restore") {
                    Button {
                        importConfigText = ""
                        importResult = nil
                        showImportSheet = true
                    } label: {
                        moreRow(icon: "square.and.arrow.down.fill", title: "Import JSON Config", subtitle: "Paste or load exported JSON to restore", color: .green)
                    }

                    Button {
                        showImportFilePicker = true
                    } label: {
                        moreRow(icon: "folder.badge.plus", title: "Import from File", subtitle: "Load a .json or .txt config file", color: .orange)
                    }
                }

                if vm.debugMode {
                    Section("Debug") {
                        NavigationLink {
                            LoginDebugScreenshotsView(vm: vm)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "ladybug.fill")
                                    .font(.title3).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Debug Screenshots").font(.subheadline.bold())
                                    Text("\(vm.debugScreenshots.count) screenshots captured").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !vm.debugScreenshots.isEmpty {
                                    let passCount = vm.debugScreenshots.filter({ $0.effectiveResult == .markedPass }).count
                                    let failCount = vm.debugScreenshots.filter({ $0.effectiveResult == .markedFail }).count
                                    HStack(spacing: 4) {
                                        if passCount > 0 {
                                            Text("\(passCount)").font(.system(.caption2, design: .monospaced, weight: .bold)).foregroundStyle(.green)
                                        }
                                        if failCount > 0 {
                                            Text("\(failCount)").font(.system(.caption2, design: .monospaced, weight: .bold)).foregroundStyle(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Debug Log") {
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title3).foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Full Debug Log").font(.subheadline.bold())
                                Text("View debug entries")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                Section("Console") {
                    if vm.globalLogs.isEmpty {
                        Text("No log entries").foregroundStyle(.tertiary)
                    } else {
                        ForEach(vm.globalLogs.prefix(50)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTime)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 80, alignment: .leading)
                                Text(entry.level.rawValue)
                                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                                    .foregroundStyle(moreLogColor(entry.level))
                                    .frame(width: 36)
                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            if showCopiedToast {
                Text("Copied to clipboard")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.green.gradient, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
        .navigationTitle("More")
        .fileExporter(isPresented: $showFileExporter, document: exportDocument, contentType: .plainText, defaultFilename: "app_state_\(dateStamp()).txt") { result in
            switch result {
            case .success: vm.log("Exported app state to file", level: .success)
            case .failure(let error): vm.log("Export failed: \(error.localizedDescription)", level: .error)
            }
        }
        .sheet(isPresented: $showImportSheet) { importConfigSheet }
        .fileImporter(isPresented: $showImportFilePicker, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                    importConfigText = text
                    importResult = nil
                    showImportSheet = true
                }
            case .failure(let error):
                vm.log("File import error: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private var importConfigSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Button {
                        if let clip = UIPasteboard.general.string { importConfigText = clip }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button { showImportFileImporter = true } label: {
                        Label("Load File", systemImage: "folder").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Spacer()

                    let byteCount = importConfigText.utf8.count
                    if byteCount > 0 {
                        Text("\(byteCount / 1024)KB")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                TextEditor(text: $importConfigText)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if importConfigText.isEmpty {
                            Text("Paste exported JSON config here...")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 14).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal)

                if let result = importResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.summary)
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.green)
                        if !result.errors.isEmpty {
                            ForEach(result.errors, id: \.self) { error in
                                Text(error)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Import Config").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportSheet = false; importConfigText = ""; importResult = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let result = AppDataExportService.shared.importJSON(importConfigText)
                        importResult = result
                        vm.log(result.summary, level: result.errors.isEmpty ? .success : .warning)
                        if result.errors.isEmpty {
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                showImportSheet = false
                                importConfigText = ""
                                importResult = nil
                            }
                        }
                    }
                    .disabled(importConfigText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showImportFileImporter, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                        importConfigText = text
                    }
                case .failure(let error):
                    vm.log("File import error: \(error.localizedDescription)", level: .error)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }

    private func moreRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func moreLogColor(_ level: PPSRLogEntry.Level) -> Color {
        switch level {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
