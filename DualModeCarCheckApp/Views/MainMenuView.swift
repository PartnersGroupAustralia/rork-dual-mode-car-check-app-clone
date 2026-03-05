import SwiftUI

struct MainMenuView: View {
    @Binding var activeMode: ActiveAppMode?
    @State private var animateIn: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("MainMenuBG")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Color.black.opacity(0.3)

                VStack(spacing: 0) {
                    Spacer().frame(height: geo.safeAreaInsets.top + 12)

                    HStack(spacing: 0) {
                        joeZone(geo: geo)
                        ignitionZone(geo: geo)
                    }
                    .frame(height: (geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom) * 0.52)

                    HStack(spacing: 0) {
                        ppsrZone(geo: geo)
                        superTestZone(geo: geo)
                    }
                    .frame(maxHeight: .infinity)

                    Spacer().frame(height: geo.safeAreaInsets.bottom + 4)
                }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                activeMode = .flowRecorder
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "record.circle")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("RECORD FLOW")
                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            }
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.red.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                    }
                    .padding(.top, geo.safeAreaInsets.top + 12)

                    Spacer()

                    HStack {
                        Button {
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                activeMode = .debugLog
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("DEBUG LOG")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            }
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 16)

                        Spacer()

                        Text("v10.0")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.15))
                            .padding(.trailing, 16)
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom + 6)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.12)) {
                animateIn = true
            }
        }
        .onDisappear {
            animateIn = false
        }
    }

    private func joeZone(geo: GeometryProxy) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .joe
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.clear

                LinearGradient(
                    colors: [.green.opacity(0.0), .green.opacity(0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse, options: .repeating.speed(0.4))
                        .shadow(color: .green.opacity(0.6), radius: 10)

                    Text("JOE\nFORTUNE")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineSpacing(2)
                        .shadow(color: .black.opacity(0.8), radius: 4)

                    Text("Login Testing")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.7))

                    HStack(spacing: 3) {
                        Text("ENTER")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.6))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.green.opacity(0.4))
                    }
                    .padding(.top, 2)
                }
                .padding(16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(x: animateIn ? 0 : -30)
        .sensoryFeedback(.impact(weight: .medium), trigger: activeMode == .joe)
    }

    private func ignitionZone(geo: GeometryProxy) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .ignition
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Color.clear

                LinearGradient(
                    colors: [.orange.opacity(0.0), .orange.opacity(0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .trailing, spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse, options: .repeating.speed(0.4))
                        .shadow(color: .orange.opacity(0.6), radius: 10)

                    Text("IGNITION\nCASINO")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .lineSpacing(2)
                        .shadow(color: .black.opacity(0.8), radius: 4)

                    Text("Login Testing")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.7))

                    HStack(spacing: 3) {
                        Text("ENTER")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.6))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.orange.opacity(0.4))
                    }
                    .padding(.top, 2)
                }
                .padding(16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(x: animateIn ? 0 : 30)
        .sensoryFeedback(.impact(weight: .medium), trigger: activeMode == .ignition)
    }

    private func ppsrZone(geo: GeometryProxy) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .ppsr
            }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.05), .cyan.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.cyan)
                            .shadow(color: .cyan.opacity(0.5), radius: 8)

                        Text("PPSR")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)

                        Text("VIN & Card Testing")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    .padding(.leading, 20)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.cyan)
                            .shadow(color: .cyan.opacity(0.5), radius: 8)

                        Text("CHECK")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)

                        HStack(spacing: 3) {
                            Text("ENTER")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.cyan.opacity(0.6))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(.cyan.opacity(0.4))
                        }
                    }
                    .padding(.trailing, 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 30)
        .sensoryFeedback(.impact(weight: .medium), trigger: activeMode == .ppsr)
    }

    private func superTestZone(geo: GeometryProxy) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                activeMode = .superTest
            }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [.purple.opacity(0.05), .purple.opacity(0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.purple)
                            .shadow(color: .purple.opacity(0.5), radius: 8)

                        Text("SUPER TEST")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)

                        Text("Full Infrastructure")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.purple.opacity(0.7))
                    }
                    .padding(.leading, 20)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "fingerprint")
                            Image(systemName: "network")
                            Image(systemName: "shield.lefthalf.filled")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.6))

                        HStack(spacing: 3) {
                            Text("ENTER")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.purple.opacity(0.6))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(.purple.opacity(0.4))
                        }
                    }
                    .padding(.trailing, 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 30)
        .sensoryFeedback(.impact(weight: .medium), trigger: activeMode == .superTest)
    }
}

nonisolated enum ActiveAppMode: String, Sendable {
    case joe
    case ignition
    case ppsr
    case superTest
    case debugLog
    case flowRecorder
}
