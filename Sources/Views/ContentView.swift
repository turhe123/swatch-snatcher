import SwiftUI

/// The MenuBarExtra popover: format picker, recent swatches, pick button, contrast checker and palettes.
struct ContentView: View {
    @ObservedObject var state = AppState.shared
    @AppStorage(Prefs.format) private var format: ColorFormat = .hex
    @AppStorage(Prefs.hotKeyLabel) private var hotKeyLabel = "C" // refreshes the shortcut hint

    private let columns = [GridItem(.adaptive(minimum: 26, maximum: 26), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SwatchSnatcher", systemImage: "drop.fill").font(.headline)
                Spacer()
                Picker("Format", selection: $format) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 100)
            }
            if state.permissionDenied { permissionBox }
            Button {
                PickerSession.shared.start()
            } label: {
                HStack {
                    Image(systemName: "eyedropper")
                    Text("Pick Color")
                    Spacer()
                    Text(state.hotKeyDisplay).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            section("Recent") {
                if state.history.isEmpty {
                    Text("No colors yet — press \(state.hotKeyDisplay) to pick one.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(state.history) { color in
                            SwatchView(color: color, flashID: "history-\(color.hex)") {
                                state.history.removeAll { $0 == color }
                            }
                        }
                    }
                }
            }
            contrastSection
            palettesSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var permissionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Screen Recording permission needed", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.bold()).foregroundStyle(.orange)
            Text("SwatchSnatcher reads pixels under the pointer. Allow it in System Settings › Privacy & Security › Screen Recording, then relaunch the app.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy Settings") { state.openPrivacySettings() }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    @ViewBuilder private var contrastSection: some View {
        section("Contrast (WCAG)") {
            if let a = state.contrastA, let b = state.contrastB {
                let ratio = a.contrast(with: b)
                HStack(spacing: 10) {
                    Text("Aa").font(.title3.bold()).foregroundStyle(a.swiftUIColor)
                        .padding(.horizontal, 8).background(RoundedRectangle(cornerRadius: 4).fill(b.swiftUIColor))
                    Text(String(format: "%.2f:1", ratio)).font(.system(.body, design: .monospaced))
                    Spacer()
                    badge("Body", pass: ratio >= 4.5)
                    badge("Large", pass: ratio >= 3.0)
                }
            } else {
                Text("Right-click two swatches and choose Compare as A / B.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func badge(_ title: String, pass: Bool) -> some View {
        Text("\(title) \(pass ? "Pass" : "Fail")")
            .font(.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill((pass ? Color.green : Color.red).opacity(0.2)))
    }

    private var palettesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Palettes").font(.subheadline.bold())
                Spacer()
                Button { state.addPalette() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("New palette")
            }
            if state.palettes.isEmpty {
                Text("Create a palette, then right-click any swatch to pin it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($state.palettes) { $palette in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Name", text: $palette.name).textFieldStyle(.plain).font(.callout.bold())
                        Button { state.export(palette) } label: { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.borderless).help("Export as text")
                        Button { state.palettes.removeAll { $0.id == palette.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete palette")
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(Array(palette.colors.enumerated()), id: \.offset) { index, color in
                            SwatchView(color: color, flashID: "\(palette.id)-\(index)") {
                                if palette.colors.indices.contains(index) { palette.colors.remove(at: index) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colors are converted to sRGB\(state.sourceSpace.map { " (source: \($0))" } ?? "").")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }
}

/// A clickable color chip: tap copies in the default format and flashes a checkmark; context menu offers more.
struct SwatchView: View {
    let color: RGBColor
    let flashID: String
    var onRemove: (() -> Void)?
    @ObservedObject private var state = AppState.shared

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.swiftUIColor)
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2)))
            .overlay {
                if state.copiedID == flashID {
                    Image(systemName: "checkmark").font(.caption.bold())
                        .foregroundStyle(color.luminance > 0.5 ? Color.black : Color.white)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: state.copiedID)
            .help(color.hex)
            .onTapGesture { state.copy(color, flashID: flashID) }
            .contextMenu {
                ForEach(ColorFormat.allCases) { f in
                    Button("Copy \(f.rawValue)") { state.copy(color, as: f, flashID: flashID) }
                }
                Divider()
                Menu("Add to Palette") {
                    ForEach(state.palettes) { p in Button(p.name) { state.add(color, to: p.id) } }
                    Button("New Palette") {
                        state.addPalette()
                        if let id = state.palettes.last?.id { state.add(color, to: id) }
                    }
                }
                Button("Compare as A") { state.contrastA = color }
                Button("Compare as B") { state.contrastB = color }
                if let onRemove {
                    Divider()
                    Button("Remove", role: .destructive, action: onRemove)
                }
            }
    }
}
