import SwiftUI

/// App entry point: a menu-bar-only app with a popover and a Settings window.
@main
struct SwatchSnatcherApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("SwatchSnatcher", systemImage: "drop.fill") {
            ContentView(state: state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
