import SwiftUI

@main
struct MacRarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appDelegate.viewModel)
        }
        .windowResizability(.contentSize)
    }
}
