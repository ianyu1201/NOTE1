import SwiftUI

@main
struct NOTE1App: App {
    @StateObject private var store = V02Store()

    var body: some Scene {
        WindowGroup {
            V02AppShellView(store: store)
                .preferredColorScheme(.light)
        }
    }
}
