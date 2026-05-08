import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = ArchiveViewModel()

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            viewModel.processFile(at: path)
        }
    }
}
