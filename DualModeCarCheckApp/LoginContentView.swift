import SwiftUI
import UniformTypeIdentifiers

struct LoginContentView: View {
    let initialMode: ActiveAppMode
    @State private var vm = LoginViewModel()
    @State private var initialModeApplied: Bool = false

    private var accentColor: Color {
        vm.isIgnitionMode ? .orange : .green
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
                case .ppsr, .superTest: break
                }
            }
        }
        .onChange(of: vm.credentials.count) { _, _ in
            vm.persistCredentials()
        }
        .onChange(of: vm.appearanceMode) { _, _ in
            vm.persistSettings()
        }
        .onChange(of: vm.debugMode) { _, _ in
            vm.persistSettings()
        }
        .onChange(of: vm.maxConcurrency) { _, _ in
            vm.persistSettings()
        }
        .onChange(of: vm.stealthEnabled) { _, _ in
            vm.persistSettings()
        }
        .onChange(of: vm.targetSite) { _, _ in
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
            VStack(spacing: 20) {
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
                    credentialSection(title: "Queued — Untested", creds: vm.untestedCredentials, color: .secondary, icon: "clock.fill")
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
            credentialsList
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Credentials")
        .searchable(text: $searchText, prompt: "Search credentials...")
        .toolbar {
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

    var body: some View {
        VStack(spacing: 0) {
            if vm.workingCredentials.isEmpty {
                ContentUnavailableView("No Working Logins", systemImage: "checkmark.shield", description: Text("Credentials that pass login tests will appear here."))
            } else {
                exportBar
                credentialsList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Working Logins")
        .toolbar {
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
            sessionList
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sessions")
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

    private var sessionList: some View {
        Group {
            if filteredAttempts.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "rectangle.stack", description: Text("Test credentials to see sessions here."))
            } else {
                List(filteredAttempts) { attempt in
                    Button { selectedAttempt = attempt } label: { LoginSessionRow(attempt: attempt) }
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
                .listStyle(.insetGrouped)
            }
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
    @State private var showProxyImport: Bool = false
    @State private var proxyBulkText: String = ""
    @State private var proxyImportReport: ProxyRotationService.ImportReport?
    @State private var showURLManager: Bool = false
    @State private var isTestingProxies: Bool = false
    @State private var showDebugScreenshots: Bool = false
    @State private var showIgnitionProxyImport: Bool = false
    @State private var ignitionProxyBulkText: String = ""
    @State private var ignitionProxyImportReport: ProxyRotationService.ImportReport?
    @State private var isTestingIgnitionProxies: Bool = false
    @State private var showDNSManager: Bool = false
    @State private var showJoeProxyImport: Bool = false
    @State private var showIgnitionTargetProxyImport: Bool = false
    @State private var targetProxyBulkText: String = ""
    @State private var targetProxyImportReport: ProxyRotationService.ImportReport?
    @State private var isTestingJoeTargetProxies: Bool = false
    @State private var isTestingIgnitionTargetProxies: Bool = false
    @State private var showVPNFileImporter: Bool = false
    @State private var vpnImportTarget: ProxyRotationService.ProxyTarget = .joe
    @AppStorage("introVideoEnabled") private var introVideoEnabled: Bool = false

    private var accentColor: Color {
        vm.isIgnitionMode ? .orange : .green
    }

    var body: some View {
        List {
            siteToggleSection
            quickActionsSection
            urlRotationSection
            joeConnectionModeSection
            ignitionConnectionModeSection
            blacklistSection
            stealthSection
            concurrencySection
            debugSection
            appearanceSection
            introVideoSection
            iCloudSection
            endpointSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showProxyImport) { proxyImportSheet }
        .sheet(isPresented: $showIgnitionProxyImport) { ignitionProxyImportSheet }
        .sheet(isPresented: $showURLManager) { urlManagerSheet }
        .sheet(isPresented: $showDNSManager) { loginDNSManagerSheet }
        .sheet(isPresented: $showJoeProxyImport) { targetProxyImportSheet(target: .joe) }
        .sheet(isPresented: $showIgnitionTargetProxyImport) { targetProxyImportSheet(target: .ignition) }
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
        .fileImporter(isPresented: $showVPNFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var imported = 0
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url),
                       let content = String(data: data, encoding: .utf8) {
                        let fileName = url.lastPathComponent
                        if let config = OpenVPNConfig.parse(fileName: fileName, content: content) {
                            vm.proxyService.importVPNConfig(config, for: vpnImportTarget)
                            imported += 1
                        } else {
                            vm.log("Failed to parse: \(fileName)", level: .warning)
                        }
                    }
                }
                if imported > 0 {
                    vm.log("Imported \(imported) OpenVPN config(s)", level: .success)
                }
            case .failure(let error):
                vm.log("VPN import error: \(error.localizedDescription)", level: .error)
            }
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

    private var urlRotationSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL Rotation").font(.body)
                    Text("\(vm.urlRotation.enabledURLs.count) of \(vm.urlRotation.activeURLs.count) URLs enabled").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(vm.isIgnitionMode ? "Ignition" : "Joe")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accentColor.opacity(0.12)).clipShape(Capsule())
            }

            Button { showURLManager = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet").foregroundStyle(accentColor)
                    Text("Manage URLs")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }

            Button {
                vm.urlRotation.enableAllURLs()
                vm.log("Re-enabled all URLs", level: .success)
            } label: {
                Label("Re-enable All URLs", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("URL Rotation")
        } footer: {
            Text("Each test uses the next enabled URL in rotation. Failed URLs are auto-disabled after 2 consecutive failures.")
        }
    }

    private var joeConnectionModeSection: some View {
        connectionModeSection(
            title: "Joe Fortune",
            target: .joe,
            color: .green,
            icon: "suit.spade.fill",
            showProxyImportBinding: $showJoeProxyImport,
            isTestingBinding: $isTestingJoeTargetProxies
        )
    }

    private var ignitionConnectionModeSection: some View {
        connectionModeSection(
            title: "Ignition",
            target: .ignition,
            color: .orange,
            icon: "flame.fill",
            showProxyImportBinding: $showIgnitionTargetProxyImport,
            isTestingBinding: $isTestingIgnitionTargetProxies
        )
    }

    private func connectionModeSection(
        title: String,
        target: ProxyRotationService.ProxyTarget,
        color: Color,
        icon: String,
        showProxyImportBinding: Binding<Bool>,
        isTestingBinding: Binding<Bool>
    ) -> some View {
        let currentMode = vm.proxyService.connectionMode(for: target)
        let proxyList = vm.proxyService.proxies(for: target)
        return Section {
            Picker(selection: Binding(
                get: { vm.proxyService.connectionMode(for: target) },
                set: { newMode in
                    withAnimation(.spring(duration: 0.3)) {
                        vm.proxyService.setConnectionMode(newMode, for: target)
                    }
                    vm.log("\(title) switched to \(newMode.label) mode", level: .success)
                }
            )) {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text("\(title) Connection")
                }
            }
            .pickerStyle(.menu)
            .sensoryFeedback(.impact(weight: .medium), trigger: currentMode)

            if currentMode == .proxy {
                HStack(spacing: 10) {
                    Image(systemName: "network").foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(title) Proxies").font(.body)
                        Text("\(proxyList.count) proxies loaded").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    proxyStatusBadge(proxies: proxyList)
                }

                Button { showProxyImportBinding.wrappedValue = true } label: {
                    Label("Import Proxies", systemImage: "doc.on.clipboard.fill")
                }

                if !proxyList.isEmpty {
                    Button {
                        guard !isTestingBinding.wrappedValue else { return }
                        isTestingBinding.wrappedValue = true
                        Task {
                            vm.log("Testing all \(proxyList.count) \(title) proxies...")
                            await vm.proxyService.testAllProxies(target: target)
                            let working = vm.proxyService.proxies(for: target).filter(\.isWorking).count
                            vm.log("\(title) proxy test: \(working)/\(proxyList.count) working", level: .success)
                            isTestingBinding.wrappedValue = false
                        }
                    } label: {
                        HStack {
                            Label("Test Proxies", systemImage: "antenna.radiowaves.left.and.right")
                            if isTestingBinding.wrappedValue { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTestingBinding.wrappedValue)

                    Button {
                        let exported = vm.proxyService.exportProxies(target: target)
                        UIPasteboard.general.string = exported
                        vm.log("Exported \(proxyList.count) \(title) proxies to clipboard", level: .success)
                    } label: {
                        Label("Export to Clipboard", systemImage: "doc.on.doc")
                    }

                    let deadCount = proxyList.filter({ !$0.isWorking && $0.lastTested != nil }).count
                    if deadCount > 0 {
                        Button(role: .destructive) {
                            vm.proxyService.removeDead(target: target)
                            vm.log("Removed \(deadCount) dead \(title) proxies")
                        } label: {
                            Label("Remove \(deadCount) Dead", systemImage: "xmark.circle")
                        }
                    }

                    ForEach(proxyList) { proxy in
                        targetProxyRow(proxy: proxy, target: target)
                    }

                    Button {
                        vm.proxyService.resetAllStatus(target: target)
                        vm.log("Reset all \(title) proxy statuses")
                    } label: {
                        Label("Reset All Status", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        vm.proxyService.removeAll(target: target)
                        vm.log("Cleared all \(title) proxies")
                    } label: {
                        Label("Clear All Proxies", systemImage: "trash")
                    }
                }
            } else if currentMode == .openvpn {
                let vpnList = vm.proxyService.vpnConfigs(for: target)
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(title) OpenVPN").font(.body)
                        Text("\(vpnList.count) configs loaded").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    let enabledCount = vpnList.filter(\.isEnabled).count
                    if enabledCount > 0 {
                        Text("\(enabledCount) active")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.indigo.opacity(0.12)).clipShape(Capsule())
                    }
                }

                Button {
                    vpnImportTarget = target
                    showVPNFileImporter = true
                } label: {
                    Label("Import .ovpn File", systemImage: "doc.badge.plus")
                }

                if !vpnList.isEmpty {
                    ForEach(vpnList) { vpn in
                        HStack(spacing: 8) {
                            Image(systemName: vpn.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vpn.isEnabled ? .indigo : .secondary)
                                .onTapGesture {
                                    vm.proxyService.toggleVPNConfig(vpn, target: target, enabled: !vpn.isEnabled)
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(vpn.fileName)
                                    .font(.system(.caption, design: .monospaced, weight: .medium))
                                    .lineLimit(1)
                                Text(vpn.displayString)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                vm.proxyService.removeVPNConfig(vpn, target: target)
                                vm.log("Removed VPN: \(vpn.fileName)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }

                    Button(role: .destructive) {
                        vm.proxyService.clearAllVPNConfigs(target: target)
                        vm.log("Cleared all \(title) OpenVPN configs")
                    } label: {
                        Label("Clear All Configs", systemImage: "trash")
                    }
                }
            } else {
                let enabled = PPSRDoHService.shared.managedProviders.filter(\.isEnabled).count
                let total = PPSRDoHService.shared.managedProviders.count
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DoH DNS Rotation").font(.body)
                        Text("\(enabled)/\(total) providers enabled").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }

                Button { showDNSManager = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack").foregroundStyle(.cyan)
                        Text("Manage DNS Servers")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            HStack {
                Text("\(title) Connection")
                Spacer()
                Text(currentMode.label)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(currentMode == .proxy ? color : currentMode == .openvpn ? .indigo : .cyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((currentMode == .proxy ? color : currentMode == .openvpn ? .indigo : .cyan).opacity(0.12))
                    .clipShape(Capsule())
            }
        } footer: {
            switch currentMode {
            case .proxy: Text("\(title) uses SOCKS5 proxies for all connections.")
            case .openvpn: Text("\(title) uses OpenVPN configs. Import .ovpn files to connect.")
            case .dns: Text("\(title) uses DoH DNS rotation for connections.")
            }
        }
    }

    private func targetProxyRow(proxy: ProxyConfig, target: ProxyRotationService.ProxyTarget) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(proxyStatusColor(proxy))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(proxy.displayString)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(proxy.statusLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(proxyStatusColor(proxy))
                    if let date = proxy.lastTested {
                        Text(date, style: .relative)
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                }
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { vm.proxyService.removeProxy(proxy, target: target) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func proxyStatusBadge(proxies: [ProxyConfig]) -> some View {
        Group {
            if !proxies.isEmpty {
                HStack(spacing: 4) {
                    let working = proxies.filter(\.isWorking).count
                    if working > 0 {
                        Text("\(working) ok")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    let dead = proxies.filter({ !$0.isWorking && $0.lastTested != nil }).count
                    if dead > 0 {
                        Text("\(dead) dead")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
            }
        }
    }

    private func proxyStatusColor(_ proxy: ProxyConfig) -> Color {
        if proxy.lastTested == nil { return .gray }
        return proxy.isWorking ? .green : .red
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

    private func targetProxyImportSheet(target: ProxyRotationService.ProxyTarget) -> some View {
        let targetName: String
        let targetColor: Color
        switch target {
        case .joe: targetName = "Joe Fortune"; targetColor = .green
        case .ignition: targetName = "Ignition"; targetColor = .orange
        case .ppsr: targetName = "PPSR"; targetColor = .blue
        }
        return NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(targetColor).frame(width: 10, height: 10)
                        Text("Import \(targetName) SOCKS5 Proxies").font(.headline)
                    }
                    Text("Paste proxies in any common format, one per line.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                            targetProxyBulkText = clipboard
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    let lineCount = targetProxyBulkText.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count
                    if lineCount > 0 {
                        Text("\(lineCount) lines").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $targetProxyBulkText)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if targetProxyBulkText.isEmpty {
                            Text("Paste SOCKS5 proxies here...\n\n127.0.0.1:1080\nuser:pass@proxy.com:9050")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 14).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                if let report = targetProxyImportReport {
                    HStack(spacing: 12) {
                        if report.added > 0 {
                            Label("\(report.added) added", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
                        }
                        if report.duplicates > 0 {
                            Label("\(report.duplicates) duplicates", systemImage: "arrow.triangle.2.circlepath").font(.caption.bold()).foregroundStyle(.orange)
                        }
                        if !report.failed.isEmpty {
                            Label("\(report.failed.count) failed", systemImage: "xmark.circle.fill").font(.caption.bold()).foregroundStyle(.red)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("\(targetName) Proxies").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if target == .joe { showJoeProxyImport = false }
                        else { showIgnitionTargetProxyImport = false }
                        targetProxyBulkText = ""
                        targetProxyImportReport = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let report = vm.proxyService.bulkImportSOCKS5(targetProxyBulkText, for: target)
                        targetProxyImportReport = report
                        if report.added > 0 {
                            vm.log("Imported \(report.added) \(targetName) SOCKS5 proxies", level: .success)
                        }
                        targetProxyBulkText = ""
                        if report.failed.isEmpty && report.added > 0 {
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                if target == .joe { showJoeProxyImport = false }
                                else { showIgnitionTargetProxyImport = false }
                                targetProxyImportReport = nil
                            }
                        }
                    }
                    .disabled(targetProxyBulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
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

    @State private var loginDNSImportText: String = ""
    @State private var showLoginDNSImport: Bool = false
    @State private var newLoginDNSName: String = ""
    @State private var newLoginDNSURL: String = ""

    private var loginDNSManagerSheet: some View {
        NavigationStack {
            List {
                if showLoginDNSImport {
                    Section("Import DNS Servers") {
                        Text("One per line. Format: Name|URL or just URL")
                            .font(.caption2).foregroundStyle(.secondary)

                        TextEditor(text: $loginDNSImportText)
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 8))
                            .frame(minHeight: 80)
                            .overlay(alignment: .topLeading) {
                                if loginDNSImportText.isEmpty {
                                    Text("Custom|https://dns.example.com/dns-query")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                        .padding(.horizontal, 12).padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }

                        HStack {
                            Button {
                                if let clip = UIPasteboard.general.string { loginDNSImportText = clip }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Spacer()
                            Button {
                                let result = PPSRDoHService.shared.bulkImportProviders(loginDNSImportText)
                                vm.log("DNS import: \(result.added) added, \(result.duplicates) dupes", level: result.added > 0 ? .success : .warning)
                                loginDNSImportText = ""
                                if result.added > 0 { withAnimation(.snappy) { showLoginDNSImport = false } }
                            } label: {
                                Label("Import", systemImage: "arrow.down.doc.fill").font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent).tint(.cyan)
                            .disabled(loginDNSImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Section("Add Single Server") {
                        TextField("Name", text: $newLoginDNSName)
                            .font(.system(.body, design: .monospaced))
                        TextField("https://dns.example.com/dns-query", text: $newLoginDNSURL)
                            .font(.system(.callout, design: .monospaced))
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            if PPSRDoHService.shared.addProvider(name: newLoginDNSName, url: newLoginDNSURL) {
                                vm.log("Added DNS: \(newLoginDNSName)", level: .success)
                                newLoginDNSName = ""
                                newLoginDNSURL = ""
                            }
                        } label: {
                            Label("Add Server", systemImage: "plus.circle.fill")
                        }
                        .disabled(newLoginDNSName.trimmingCharacters(in: .whitespaces).isEmpty || newLoginDNSURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                let enabled = PPSRDoHService.shared.managedProviders.filter(\.isEnabled).count
                Section {
                    ForEach(PPSRDoHService.shared.managedProviders) { provider in
                        HStack(spacing: 10) {
                            Button {
                                PPSRDoHService.shared.toggleProvider(id: provider.id, enabled: !provider.isEnabled)
                            } label: {
                                Image(systemName: provider.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(provider.isEnabled ? .cyan : .secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(provider.name).font(.system(.subheadline, design: .monospaced, weight: .medium))
                                    if provider.isDefault {
                                        Text("DEFAULT")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.cyan.opacity(0.7))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Color.cyan.opacity(0.1)).clipShape(Capsule())
                                    }
                                }
                                Text(provider.url.replacingOccurrences(of: "https://", with: ""))
                                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                PPSRDoHService.shared.deleteProvider(id: provider.id)
                                vm.log("Deleted DNS: \(provider.name)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("DNS Servers (\(enabled)/\(PPSRDoHService.shared.managedProviders.count))")
                }

                Section {
                    Button {
                        withAnimation(.snappy) { showLoginDNSImport.toggle() }
                    } label: {
                        Label(showLoginDNSImport ? "Hide Import" : "Import / Add Servers", systemImage: "plus.circle.fill")
                    }
                    Button {
                        PPSRDoHService.shared.enableAll()
                        vm.log("Enabled all DNS providers", level: .success)
                    } label: {
                        Label("Enable All", systemImage: "checkmark.circle")
                    }
                    Button {
                        PPSRDoHService.shared.resetToDefaults()
                        vm.log("Reset DNS to defaults", level: .success)
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                    }
                } header: {
                    Text("Actions")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("DNS Manager").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showDNSManager = false } }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
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

    private var endpointSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Target") {
                    HStack(spacing: 4) {
                        Circle().fill(endpointColor).frame(width: 6, height: 6)
                        Text(vm.connectionStatus == .connected ? "Live" : vm.connectionStatus.rawValue)
                            .font(.system(.body, design: .monospaced)).foregroundStyle(endpointColor)
                    }
                }
                LabeledContent("Site") { Text(vm.urlRotation.currentSiteName).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                LabeledContent("URLs") { Text("\(vm.urlRotation.enabledURLs.count) active").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                LabeledContent("Timeout") { Text("\(Int(vm.testTimeout))s per test").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
            }

            Button {
                Task { await vm.testConnection() }
            } label: {
                HStack {
                    if vm.connectionStatus == .connecting { ProgressView().controlSize(.small) }
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(vm.connectionStatus == .connecting ? "Testing..." : "Test Connection")
                }
            }
            .disabled(vm.connectionStatus == .connecting)
        } header: {
            Text("Live Endpoint")
        }
    }

    private var endpointColor: Color {
        switch vm.connectionStatus {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .secondary
        case .error: .red
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

    private var proxyImportSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bulk Import SOCKS5 Proxies").font(.headline)
                    Text("Paste proxies in any common format, one per line.").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Supported formats:").font(.caption.bold()).foregroundStyle(.secondary)
                        Group {
                            Text("host:port")
                            Text("user:pass@host:port")
                            Text("socks5://host:port")
                            Text("socks5://user:pass@host:port")
                            Text("user:pass:host:port")
                            Text("host:port:user:pass")
                        }
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                            proxyBulkText = clipboard
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    let lineCount = proxyBulkText.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count
                    if lineCount > 0 {
                        Text("\(lineCount) lines")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $proxyBulkText)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if proxyBulkText.isEmpty {
                            Text("Paste SOCKS5 proxies here...\n\n127.0.0.1:1080\nuser:pass@proxy.com:9050\nsocks5://10.0.0.1:1080")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 14).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                if let report = proxyImportReport {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            if report.added > 0 {
                                Label("\(report.added) added", systemImage: "checkmark.circle.fill")
                                    .font(.caption.bold()).foregroundStyle(.green)
                            }
                            if report.duplicates > 0 {
                                Label("\(report.duplicates) duplicates", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption.bold()).foregroundStyle(.orange)
                            }
                            if !report.failed.isEmpty {
                                Label("\(report.failed.count) failed", systemImage: "xmark.circle.fill")
                                    .font(.caption.bold()).foregroundStyle(.red)
                            }
                        }
                        if !report.failed.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Failed lines:").font(.caption2.bold()).foregroundStyle(.red.opacity(0.8))
                                ForEach(Array(report.failed.prefix(5).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.red.opacity(0.7))
                                        .lineLimit(1)
                                }
                                if report.failed.count > 5 {
                                    Text("...and \(report.failed.count - 5) more")
                                        .font(.caption2).foregroundStyle(.red.opacity(0.5))
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(.rect(cornerRadius: 8))
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import Proxies").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showProxyImport = false
                        proxyBulkText = ""
                        proxyImportReport = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let report = vm.proxyService.bulkImportSOCKS5(proxyBulkText)
                        proxyImportReport = report
                        if report.added > 0 {
                            vm.log("Imported \(report.added) SOCKS5 proxies (\(report.duplicates) duplicates, \(report.failed.count) failed)", level: .success)
                        } else if report.duplicates > 0 {
                            vm.log("All \(report.duplicates) proxies already exist", level: .warning)
                        } else {
                            vm.log("Import failed: could not parse any proxy lines", level: .error)
                        }
                        proxyBulkText = ""
                        if report.failed.isEmpty && report.added > 0 {
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                showProxyImport = false
                                proxyImportReport = nil
                            }
                        }
                    }
                    .disabled(proxyBulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var ignitionProxyImportSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("Import Ignition SOCKS5 Proxies").font(.headline)
                    }
                    Text("Paste proxies for Ignition Casino, one per line.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                            ignitionProxyBulkText = clipboard
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    let lineCount = ignitionProxyBulkText.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count
                    if lineCount > 0 {
                        Text("\(lineCount) lines").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $ignitionProxyBulkText)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10)).frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if ignitionProxyBulkText.isEmpty {
                            Text("Paste Ignition SOCKS5 proxies here...\n\n127.0.0.1:1080\nuser:pass@proxy.com:9050")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 14).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                if let report = ignitionProxyImportReport {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            if report.added > 0 {
                                Label("\(report.added) added", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
                            }
                            if report.duplicates > 0 {
                                Label("\(report.duplicates) duplicates", systemImage: "arrow.triangle.2.circlepath").font(.caption.bold()).foregroundStyle(.orange)
                            }
                            if !report.failed.isEmpty {
                                Label("\(report.failed.count) failed", systemImage: "xmark.circle.fill").font(.caption.bold()).foregroundStyle(.red)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Ignition Proxies").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showIgnitionProxyImport = false
                        ignitionProxyBulkText = ""
                        ignitionProxyImportReport = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let report = vm.proxyService.bulkImportSOCKS5(ignitionProxyBulkText, forIgnition: true)
                        ignitionProxyImportReport = report
                        if report.added > 0 {
                            vm.log("Imported \(report.added) Ignition SOCKS5 proxies", level: .success)
                        }
                        ignitionProxyBulkText = ""
                        if report.failed.isEmpty && report.added > 0 {
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                showIgnitionProxyImport = false
                                ignitionProxyImportReport = nil
                            }
                        }
                    }
                    .disabled(ignitionProxyBulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    @State private var urlImportText: String = ""
    @State private var showURLImportBox: Bool = false
    @State private var urlViewingIgnition: Bool = false

    private var urlManagerSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { urlViewingIgnition = false }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "suit.spade.fill")
                                Text("Joe").font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(!urlViewingIgnition ? Color.green : Color(.tertiarySystemFill))
                            .foregroundStyle(!urlViewingIgnition ? .white : .secondary)
                        }
                        .clipShape(.rect(cornerRadii: .init(topLeading: 10, bottomLeading: 10)))

                        Button {
                            withAnimation(.spring(duration: 0.3)) { urlViewingIgnition = true }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                Text("Ignition").font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(urlViewingIgnition ? Color.orange : Color(.tertiarySystemFill))
                            .foregroundStyle(urlViewingIgnition ? .white : .secondary)
                        }
                        .clipShape(.rect(cornerRadii: .init(bottomTrailing: 10, topTrailing: 10)))
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if showURLImportBox {
                    Section("Import URLs") {
                        TextEditor(text: $urlImportText)
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 8))
                            .frame(minHeight: 100)
                            .overlay(alignment: .topLeading) {
                                if urlImportText.isEmpty {
                                    Text("One URL per line...\nhttps://domain.com/login")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.quaternary)
                                        .padding(.horizontal, 12).padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }

                        HStack {
                            Button {
                                if let clip = UIPasteboard.general.string { urlImportText = clip }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Spacer()
                            Button {
                                let result = vm.urlRotation.bulkImportURLs(urlImportText, forIgnition: urlViewingIgnition)
                                vm.log("URL import: \(result.added) added, \(result.duplicates) dupes, \(result.invalid) invalid", level: result.added > 0 ? .success : .warning)
                                urlImportText = ""
                                if result.added > 0 {
                                    withAnimation(.snappy) { showURLImportBox = false }
                                }
                            } label: {
                                Label("Import", systemImage: "arrow.down.doc.fill").font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(urlViewingIgnition ? .orange : .green)
                            .disabled(urlImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                let urlList = urlViewingIgnition ? vm.urlRotation.ignitionURLs : vm.urlRotation.joeURLs
                Section {
                    ForEach(urlList) { urlEntry in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(urlEntry.isEnabled ? (urlViewingIgnition ? Color.orange : Color.green) : Color.red.opacity(0.5))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(urlEntry.host)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(urlEntry.isEnabled ? .primary : .secondary)
                                    .strikethrough(!urlEntry.isEnabled)
                                HStack(spacing: 6) {
                                    if urlEntry.failCount > 0 {
                                        Text("\(urlEntry.failCount) fails").font(.caption2).foregroundStyle(.red)
                                    }
                                    if urlEntry.totalAttempts > 0 {
                                        Text(urlEntry.formattedSuccessRate).font(.caption2).foregroundStyle(.secondary)
                                        Text(urlEntry.formattedAvgResponse).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                vm.urlRotation.toggleURL(id: urlEntry.id, enabled: !urlEntry.isEnabled)
                            } label: {
                                Image(systemName: urlEntry.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(urlEntry.isEnabled ? .green : .red.opacity(0.5))
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.urlRotation.deleteURL(id: urlEntry.id)
                                vm.log("Deleted URL: \(urlEntry.host)")
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    let enabled = urlList.filter(\.isEnabled).count
                    Text("\(urlViewingIgnition ? "Ignition" : "Joe") URLs (\(enabled)/\(urlList.count))")
                }

                Section {
                    Button {
                        withAnimation(.snappy) { showURLImportBox.toggle() }
                    } label: {
                        Label(showURLImportBox ? "Hide Import" : "Import URLs", systemImage: "plus.circle.fill")
                    }

                    Button {
                        vm.urlRotation.enableAllURLs()
                        vm.log("Re-enabled all URLs", level: .success)
                    } label: {
                        Label("Re-enable All", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        vm.urlRotation.resetPerformanceStats()
                        vm.log("Reset URL performance stats")
                    } label: {
                        Label("Reset Stats", systemImage: "chart.bar.xaxis")
                    }

                    Button {
                        vm.urlRotation.resetToDefaults(forIgnition: urlViewingIgnition)
                        vm.log("Reset \(urlViewingIgnition ? "Ignition" : "Joe") URLs to defaults", level: .success)
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                    }

                    if !urlList.isEmpty {
                        Button(role: .destructive) {
                            vm.urlRotation.deleteAllURLs(forIgnition: urlViewingIgnition)
                            vm.log("Deleted all \(urlViewingIgnition ? "Ignition" : "Joe") URLs")
                        } label: {
                            Label("Delete All \(urlViewingIgnition ? "Ignition" : "Joe") URLs", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Actions")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("URL Manager").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showURLManager = false } }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}

// MARK: - More Menu

struct LoginMoreMenuView: View {
    let vm: LoginViewModel

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LoginSettingsContentView(vm: vm)
                } label: {
                    moreRow(icon: "gearshape.fill", title: "Settings", subtitle: "Automation, stealth, proxies & more", color: .secondary)
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
        .navigationTitle("More")
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
