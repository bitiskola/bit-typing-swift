import SwiftUI

// MARK: - Running the App

@main
struct BITTypingApp: App {
    @State private var state = AppState()

    init() {
        // Headless engine check for CI / Command Line Tools environments
        // without Xcode's testing libraries.
        if CommandLine.arguments.contains("--verify-engine") {
            let (passed, failed) = MainActor.assumeIsolated {
                EngineVerify.run()
            }
            for (name, detail) in failed {
                print("FAIL \(name) \(detail)")
            }
            print("\(passed) passed, \(failed.count) failed")
            exit(failed.isEmpty ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
        }
        // Unified in-app bar (Chrome-style): no separate native title strip,
        // content extends edge to edge; traffic lights float over the top bar.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // About / Options moved out of the window top bar into
            // File, so the in-window chrome stays to tabs + lesson only.
            CommandGroup(after: .newItem) {
                Button(state.t("options")) { state.showingOptions = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button(state.t("about")) { state.showingAbout = true }
            }
        }
    }
}
