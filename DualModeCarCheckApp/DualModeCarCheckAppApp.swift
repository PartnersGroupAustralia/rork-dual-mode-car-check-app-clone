import SwiftUI

@main
struct DualModeCarCheckAppApp: App {
    @AppStorage("activeAppMode") private var activeModeRaw: String = ""
    @AppStorage("introVideoEnabled") private var introVideoEnabled: Bool = false
    @State private var introFinished: Bool = false
    @State private var nordInitialized: Bool = false

    private var activeMode: ActiveAppMode? {
        ActiveAppMode(rawValue: activeModeRaw)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if introVideoEnabled && !introFinished {
                    IntroVideoView(isFinished: $introFinished)
                        .transition(.opacity)
                } else if let mode = activeMode {
                    Group {
                        switch mode {
                        case .joe:
                            LoginContentView(initialMode: .joe)
                        case .ignition:
                            LoginContentView(initialMode: .ignition)
                        case .ppsr:
                            ContentView()
                        case .superTest:
                            SuperTestContainerView()
                        case .debugLog:
                            NavigationStack {
                                DebugLogView()
                            }
                            .overlay(alignment: .bottomLeading) { MainMenuButton() }
                            .preferredColorScheme(.dark)
                        case .flowRecorder:
                            NavigationStack {
                                FlowRecorderView()
                            }
                            .overlay(alignment: .bottomLeading) { MainMenuButton() }
                            .preferredColorScheme(.dark)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                } else {
                    MainMenuView(activeMode: Binding(
                        get: { activeMode },
                        set: { newMode in
                            if let m = newMode {
                                activeModeRaw = m.rawValue
                            } else {
                                activeModeRaw = ""
                            }
                        }
                    ))
                    .transition(.opacity)
                }
            }
            .task {
                if !nordInitialized {
                    nordInitialized = true
                    let nord = NordVPNService.shared
                    if !nord.hasAccessKey {
                        nord.setAccessKey("e9f2abb927fb478e7c61afed90ee4cae8e3094b47418748ea7e518c955a0a0d1")
                    }
                    if nord.hasAccessKey && !nord.hasPrivateKey {
                        await nord.fetchPrivateKey()
                    }
                }
            }
        }
    }
}
