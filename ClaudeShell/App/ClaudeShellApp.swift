import SwiftUI

@main
struct ClaudeShellApp: App {
    var body: some Scene {
        WindowGroup {
            TerminalView()
                .preferredColorScheme(.dark)
        }
    }
}
