import AppKit
import ScreenCaptureKit
import SwiftUI

/// Live pixel data shown by the loupe.
@MainActor
final class LoupeModel: ObservableObject {
    @Published var pixels: [RGBColor] = []
    var center: RGBColor? { pixels.count == PickerSession.grid * PickerSession.grid ? pixels[pixels.count / 2] : nil }
}

/// Window that can take key focus while borderless, so Escape and clicks reach us.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Runs one color-picking session: click-catching overlays, the loupe window, and ScreenCaptureKit sampling at ~30 fps.
@MainActor
final class PickerSession {
    static let shared = PickerSession()
    static let grid = 9
    static let loupeSize = CGSize(width: 150, height: 176)

    private let model = LoupeModel()
    private var overlays: [NSWindow] = []
    private var loupe: NSPanel?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var content: SCShareableContent?
    private var capturing = false
    private var active = false

    func start() {
        guard !active else { return }
        let state = AppState.shared
        guard CGPreflightScreenCaptureAccess() else {
            state.permissionDenied = !CGRequestScreenCaptureAccess()
            return
        }
        state.permissionDenied = false
        active = true
        model.pixels = []
        NSApp.activate(ignoringOtherApps: true)
        showWindows()
        Task {
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                state.permissionDenied = true
                end()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.handle(event)
            return nil
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.end() } // click landed outside our overlays
        } as Any)
    }

    func end() {
        guard active else { return }
        active = false
        timer?.invalidate()
        timer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        loupe?.orderOut(nil)
        content = nil
        NSCursor.arrow.set()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown where event.keyCode == 53: end() // Escape
        case .leftMouseDown:
            guard currentScreen() != nil, let color = model.center else { end(); return }
            AppState.shared.record(color)
            if !UserDefaults.standard.bool(forKey: Prefs.continuous) { end() }
        case .rightMouseDown: end()
        default: break
        }
    }

    private func showWindows() {
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = NSColor(white: 0, alpha: 0.001)
            w.level = .screenSaver
            w.ignoresMouseEvents = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.orderFrontRegardless()
            overlays.append(w)
        }
        overlays.first?.makeKey()
        if loupe == nil {
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.loupeSize),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: LoupeView(model: model))
            loupe = panel
        }
        positionLoupe()
        loupe?.orderFrontRegardless()
    }

    private func currentScreen() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }

    /// Keeps the loupe beside the pointer, flipping sides near screen edges.
    private func positionLoupe() {
        guard let loupe, let screen = currentScreen() else { return }
        let loc = NSEvent.mouseLocation, size = Self.loupeSize, gap: CGFloat = 24
        var x = loc.x + gap, y = loc.y - gap - size.height
        if x + size.width > screen.frame.maxX { x = loc.x - gap - size.width }
        if y < screen.frame.minY { y = loc.y + gap }
        loupe.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func tick() {
        guard active else { return }
        NSCursor.crosshair.set()
        positionLoupe()
        capture()
    }

    /// Captures a grid×grid native-pixel region centred on the pointer, computed per screen scale factor.
    private func capture() {
        guard !capturing, let content, let screen = currentScreen(),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == number }) else { return }
        let loc = NSEvent.mouseLocation, scale = screen.backingScaleFactor
        let px = ((loc.x - screen.frame.minX) * scale).rounded(.down)
        let py = ((screen.frame.maxY - loc.y) * scale).rounded(.down)
        let half = CGFloat(Self.grid / 2), side = CGFloat(Self.grid) / scale
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: (px - half) / scale, y: (py - half) / scale, width: side, height: side)
        config.width = Self.grid
        config.height = Self.grid
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB
        let spaceName = screen.colorSpace?.localizedName
        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  active, let pixels = Self.sRGBPixels(of: image) else { return }
            model.pixels = pixels
            AppState.shared.sourceSpace = spaceName
        }
    }

    /// Redraws the capture into an sRGB bitmap so wide-gamut sources are converted before reading values.
    private static func sRGBPixels(of image: CGImage) -> [RGBColor]? {
        let n = grid
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        return (0..<(n * n)).map { i in
            RGBColor(r: Double(buf[i * 4]) / 255, g: Double(buf[i * 4 + 1]) / 255, b: Double(buf[i * 4 + 2]) / 255)
        }
    }
}

/// Circular magnifier showing the sampled pixel grid with the centre pixel outlined and its HEX below.
struct LoupeView: View {
    @ObservedObject var model: LoupeModel
    private let n = PickerSession.grid

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.black.opacity(0.6))
                if model.pixels.count == n * n {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(0..<n, id: \.self) { row in
                            GridRow {
                                ForEach(0..<n, id: \.self) { col in
                                    Rectangle().fill(model.pixels[row * n + col].swiftUIColor)
                                }
                            }
                        }
                    }
                }
                Rectangle().stroke(Color.white, lineWidth: 2)
                    .frame(width: 150 / CGFloat(n), height: 150 / CGFloat(n))
                    .shadow(color: .black, radius: 1)
            }
            .frame(width: 150, height: 150)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 3))
            Text(model.center?.hex ?? "…")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .foregroundStyle(.white)
        }
        .frame(width: PickerSession.loupeSize.width, height: PickerSession.loupeSize.height)
    }
}
