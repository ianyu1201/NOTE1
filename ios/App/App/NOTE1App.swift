import SwiftUI

@main
struct NOTE1App: App {
    @StateObject private var store = NoteStore()

    var body: some Scene {
        WindowGroup {
            AppShellView(store: store)
                .preferredColorScheme(.light)
        }
    }
}
