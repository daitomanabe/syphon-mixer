import AppKit
import CoreGraphics
import MetalKit

final class OutputWindowController {
    var onScreensChanged: (() -> Void)?

    private let outputView: MTKView
    private var outputWindow: NSWindow?
    private var selectedDisplayID: CGDirectDisplayID?
    private var fullscreenEnabled = false

    init(outputView: MTKView) {
        self.outputView = outputView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        rebuildWindow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isFullscreenEnabled: Bool {
        fullscreenEnabled
    }

    var canFullscreen: Bool {
        !displayOptions().isEmpty
    }

    var currentSelectedDisplayID: CGDirectDisplayID? {
        selectFallbackDisplayIfNeeded()
        return selectedDisplayID
    }

    func displayOptions() -> [(id: CGDirectDisplayID, label: String)] {
        selectFallbackDisplayIfNeeded()
        return externalScreens().enumerated().compactMap { index, screen in
            guard let id = Self.displayID(for: screen) else { return nil }
            return (id, Self.label(for: screen, id: id, externalIndex: index))
        }
    }

    func setSelectedDisplayID(_ id: CGDirectDisplayID?) {
        let validIDs = Set(externalScreens().compactMap { Self.displayID(for: $0) })
        selectedDisplayID = id.flatMap { validIDs.contains($0) ? $0 : nil }
        selectFallbackDisplayIfNeeded()
        if fullscreenEnabled {
            rebuildWindow()
        }
    }

    func setFullscreenEnabled(_ enabled: Bool) {
        fullscreenEnabled = enabled && selectedExternalScreen() != nil
        rebuildWindow()
    }

    func showPreview() {
        fullscreenEnabled = false
        rebuildWindow()
    }

    func displayStatus() -> String {
        let options = displayOptions()
        guard !options.isEmpty else {
            return "main preview, no external display"
        }

        let target = options.first(where: { $0.id == selectedDisplayID })?.label ?? options[0].label
        return fullscreenEnabled ? "fullscreen \(target)" : "main preview, target \(target)"
    }

    private func rebuildWindow() {
        let screen = fullscreenEnabled ? selectedExternalScreen() : nil
        let targetScreen = screen ?? primaryScreen()
        let frame = screen?.frame ?? Self.previewFrame(on: targetScreen)
        let styleMask: NSWindow.StyleMask = screen == nil ? [.titled, .miniaturizable, .resizable] : [.borderless]

        outputWindow?.contentView = nil
        outputWindow?.orderOut(nil)

        outputView.removeFromSuperview()
        outputView.translatesAutoresizingMaskIntoConstraints = true
        outputView.frame = NSRect(origin: .zero, size: frame.size)
        outputView.autoresizingMask = [.width, .height]
        outputView.drawableSize = CGSize(
            width: frame.width * targetScreen.backingScaleFactor,
            height: frame.height * targetScreen.backingScaleFactor
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        window.title = "Syphon Mixer Output"
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = screen == nil
        window.level = screen == nil ? .normal : .screenSaver
        window.collectionBehavior = screen == nil ? [] : [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .black
        window.contentView = outputView
        window.makeKeyAndOrderFront(nil)
        if screen != nil {
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
        }
        outputWindow = window
    }

    private func selectedExternalScreen() -> NSScreen? {
        selectFallbackDisplayIfNeeded()
        if let selectedDisplayID,
           let screen = externalScreens().first(where: { Self.displayID(for: $0) == selectedDisplayID }) {
            return screen
        }

        return nil
    }

    private func externalScreens() -> [NSScreen] {
        let primaryID = Self.displayID(for: primaryScreen())
        return NSScreen.screens.filter { Self.displayID(for: $0) != primaryID }
    }

    private func primaryScreen() -> NSScreen {
        NSScreen.screens.first ?? NSScreen.main!
    }

    private func selectFallbackDisplayIfNeeded() {
        let screens = externalScreens()
        let validIDs = Set(screens.compactMap { Self.displayID(for: $0) })
        if let selectedDisplayID, validIDs.contains(selectedDisplayID) {
            return
        }

        selectedDisplayID = screens.compactMap { Self.displayID(for: $0) }.first
        if selectedDisplayID == nil {
            fullscreenEnabled = false
        }
    }

    @objc private func screenParametersChanged() {
        if fullscreenEnabled && selectedExternalScreen() == nil {
            fullscreenEnabled = false
        }
        rebuildWindow()
        onScreensChanged?()
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    private static func label(for screen: NSScreen, id: CGDirectDisplayID, externalIndex: Int) -> String {
        let frame = screen.frame
        return "External \(externalIndex + 1) - Display \(id)  \(Int(frame.width))x\(Int(frame.height))"
    }

    private static func previewFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(960.0, visible.width * 0.48)
        let height = width * 9.0 / 16.0
        let x = visible.maxX - width - 24.0
        let y = visible.minY + 24.0
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
