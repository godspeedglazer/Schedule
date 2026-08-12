import AppKit

// A macOS application starts on the process main thread. AppDelegate is
// explicitly MainActor-isolated, so make that invariant visible to Swift
// instead of scheduling its creation onto a Task and then blocking the main
// thread waiting for that Task.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate: NSObject & NSApplicationDelegate
    if Bundle.main.bundleIdentifier == "com.erichspringer.sched.notification-lab" {
        delegate = NotificationLabDelegate()
    } else {
        delegate = AppDelegate()
    }
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
