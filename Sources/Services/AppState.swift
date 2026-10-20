import AppKit
import Carbon.HIToolbox
import SwiftUI

/// UserDefaults keys shared by `@AppStorage` views and services.
enum Prefs {
    static let format = "defaultFormat"
    static let continuous = "continuousMode"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyMods = "hotKeyMods"
    static let hotKeyLabel = "hotKeyLabel"
    static let defaultMods = cmdKey | optionKey
}

/// Central app model: owns history, palettes, the contrast pair, clipboard copying and JSON persistence.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var history: [RGBColor] = [] { didSet { save() } }
    @Published var palettes: [Palette] = [] { didSet { save() } }
    @Published var permissionDenied = false
    @Published var sourceSpace: String?
    @Published var contrastA: RGBColor?
    @Published var contrastB: RGBColor?
    @Published var copiedID: String?

    let hotKey = HotKeyManager()
    private var loading = true
    private static let historyLimit = 50

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("SwatchSnatcher", isDirectory: true).appendingPathComponent("library.json")
    }

    var format: ColorFormat {
        ColorFormat(rawValue: UserDefaults.standard.string(forKey: Prefs.format) ?? "") ?? .hex
    }

    var hotKeyDisplay: String {
        let d = UserDefaults.standard
        let mods = d.object(forKey: Prefs.hotKeyMods) as? Int ?? Prefs.defaultMods
        return HotKeyManager.symbols(for: mods) + (d.string(forKey: Prefs.hotKeyLabel) ?? "C")
    }

    private init() {
        load()
        loading = false
        hotKey.onPress = { PickerSession.shared.start() }
        applyHotKey()
    }

    func applyHotKey() {
        let d = UserDefaults.standard
        let code = d.object(forKey: Prefs.hotKeyCode) as? Int ?? kVK_ANSI_C
        let mods = d.object(forKey: Prefs.hotKeyMods) as? Int ?? Prefs.defaultMods
        hotKey.register(keyCode: UInt32(code), modifiers: UInt32(mods))
    }

    /// Adds a freshly picked color to the front of history (deduplicated, capped) and copies it.
    func record(_ color: RGBColor) {
        var list = history.filter { $0 != color }
        list.insert(color, at: 0)
        history = Array(list.prefix(Self.historyLimit))
        copy(color, flashID: "history-\(color.hex)")
    }

    func copy(_ color: RGBColor, as format: ColorFormat? = nil, flashID: String? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(color.formatted(format ?? self.format), forType: .string)
        guard let flashID else { return }
        copiedID = flashID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.copiedID == flashID { self?.copiedID = nil }
        }
    }

    func addPalette() {
        palettes.append(Palette(name: "Palette \(palettes.count + 1)"))
    }

    func add(_ color: RGBColor, to paletteID: UUID) {
        guard let i = palettes.firstIndex(where: { $0.id == paletteID }) else { return }
        palettes[i].colors.append(color)
    }

    /// Writes the palette as a plain text list (one color per line in the default format).
    func export(_ palette: Palette) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(palette.name).txt"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = palette.colors.map { $0.formatted(format) }.joined(separator: "\n") + "\n"
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch {
            NSAlert(error: error).runModal()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let lib = try? JSONDecoder().decode(Library.self, from: data) else { return }
        history = Array(lib.history.prefix(Self.historyLimit))
        palettes = lib.palettes
    }

    private func save() {
        guard !loading, let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Library(history: history, palettes: palettes))
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("SwatchSnatcher: failed to save library: \(error.localizedDescription)")
        }
    }
}
