import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// Settings window: hotkey recorder, default format, continuous mode and launch at login.
struct SettingsView: View {
    @AppStorage(Prefs.format) private var format: ColorFormat = .hex
    @AppStorage(Prefs.continuous) private var continuous = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            LabeledContent("Pick hotkey") { HotKeyRecorder() }
            Picker("Default format", selection: $format) {
                ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("After picking", selection: $continuous) {
                Text("Close the loupe").tag(false)
                Text("Stay in continuous mode").tag(true)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Text("Picked colors are converted to sRGB, even on wide-gamut (Display P3) screens.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control that captures the next modifier+key combination as the global hotkey.
struct HotKeyRecorder: View {
    @AppStorage(Prefs.hotKeyCode) private var keyCode = kVK_ANSI_C
    @AppStorage(Prefs.hotKeyMods) private var mods = Prefs.defaultMods
    @AppStorage(Prefs.hotKeyLabel) private var label = "C"
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut… (Esc cancels)" : HotKeyManager.symbols(for: mods) + label) {
            recording ? stop() : start()
        }
        .frame(minWidth: 140)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        AppState.shared.hotKey.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let carbon = HotKeyManager.carbonModifiers(event.modifierFlags)
            guard carbon & (cmdKey | optionKey | controlKey) != 0 else { NSSound.beep(); return nil }
            keyCode = Int(event.keyCode)
            mods = carbon
            label = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { AppState.shared.applyHotKey() }
        recording = false
    }
}
