import SwiftUI

@main
struct Quick_AIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Quick AI", systemImage: "sparkle") {
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Quick AI") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
        }
    }
}
