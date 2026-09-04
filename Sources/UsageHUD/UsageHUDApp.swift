import AppKit

/// AppKit owns the lifecycle: every window this app shows is built by
/// `AppDelegate`.
///
/// This used to be a SwiftUI `App` whose only scene was `Settings { EmptyView() }`,
/// present purely to satisfy `App.body`. Newer SDKs materialise that scene as a
/// real, empty "Usage HUD Settings" window, so the scene is gone and the app
/// starts `NSApplication` directly. The Settings window the app actually uses
/// is created on demand by `AppDelegate.showSettings()`.
@main
@MainActor
enum UsageHUDMain {
    /// `NSApplication.delegate` is a weak reference, so the delegate has to be
    /// held somewhere that outlives `main()`.
    private static var delegate: AppDelegate?

    static func main() {
        // A child process (Codex/Claude CLI) that exits early must not take
        // the whole app down when we write to its stdin.
        ChildProcessInput.installSIGPIPEGuard()
        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        application.run()
    }
}
