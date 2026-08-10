import AppKit

let app = NSApplication.shared
var delegate: AppDelegate!
let sem = DispatchSemaphore(value: 0)
Task { @MainActor in
    delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    sem.signal()
}
sem.wait()
app.run()
