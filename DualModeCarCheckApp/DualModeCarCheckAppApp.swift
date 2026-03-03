import SwiftUI

@main
struct DualModeCarCheckAppApp: App {
    @AppStorage("productMode") private var modeRaw: String = ProductMode.ppsr.rawValue
    @AppStorage("hasSelectedMode") private var hasSelectedMode: Bool = false
    @AppStorage("introVideoEnabled") private var introVideoEnabled: Bool = false
    @State private var introFinished: Bool = false

    private var currentMode: ProductMode {
        ProductMode(rawValue: modeRaw) ?? .ppsr
    }

    var body: some Scene {
        WindowGroup {
            if introVideoEnabled && !introFinished {
                IntroVideoView(isFinished: $introFinished)
                    .transition(.opacity)
            } else if hasSelectedMode {
                Group {
                    if currentMode.isLoginMode {
                        LoginContentView()
                    } else {
                        ContentView()
                    }
                }
                .transition(.opacity)
            } else {
                ModeSelectorView(hasSelectedMode: $hasSelectedMode)
                    .transition(.opacity)
            }
        }
    }
}
