import SwiftUI

struct SuperTestContainerView: View {
    var body: some View {
        NavigationStack {
            SuperTestView()
        }
        .overlay(alignment: .bottomLeading) { MainMenuButton() }
        .preferredColorScheme(.dark)
    }
}
