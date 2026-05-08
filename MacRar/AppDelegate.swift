import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = ArchiveViewModel()

    func applicationDidFinishLaunching(_: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleAppleEvent(_:replyEvent:)),
            forEventClass: AEEventClass("aevt".fourCharCode),
            andEventID: AEEventID("odoc".fourCharCode)
        )
    }

    func application(_: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            viewModel.processFile(at: path)
        }
    }

    @objc private func handleAppleEvent(_ event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor) {
        guard let descriptorList = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        for index in 1 ... descriptorList.numberOfItems {
            guard let urlStr = descriptorList.atIndex(index)?.stringValue,
                  let url = URL(string: urlStr) else { continue }
            viewModel.processFile(at: url.path)
        }
    }
}

private extension String {
    var fourCharCode: UInt32 {
        utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
