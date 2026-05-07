import SwiftUI

@main
struct AppMacRar: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowResizability(.contentSize)
    }
}
