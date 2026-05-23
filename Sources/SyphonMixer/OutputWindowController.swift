import AppKit
import CoreGraphics
import MetalKit

final class OutputWindowController {
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

    func displayOptions() -> [(id: CGDirectDisplayID, label: String)] {
        externalScreens().compactMap { screen in
            guard let id = Self.displayID(for: screen) else { return nil }
            return (id, Self.label(for: screen, id: id))
        }
    }

    func setSelectedDisplayID(_ id: CGDirectDisplayID?) {
        selectedDisplayID = id
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

    private func rebuildWindow() {
        let screen = fullscreenEnabled ? selectedExternalScreen() : nil
        let frame = screen?.frame ?? Self.previewFrame(on: primaryScreen())
        let styleMask: NSWindow.StyleMask = screen == nil ? [.titled, .miniaturizable, .resizable] : [.borderless]

        outputWindow?.contentView = nil
        outputWindow?.orderOut(nil)

        let window = NSWindow(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false,
            screen: screen ?? primaryScreen()
        )
        window.title = "Syphon Mixer Output"
        window.contentView = outputView
        window.isReleasedWhenClosed = false
        window.level = screen == nil ? .normal : .screenSaver
        window.collectionBehavior = screen == nil ? [] : [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .black
        window.makeKeyAndOrderFront(nil)
        outputWindow = window
    }

    private func selectedExternalScreen() -> NSScreen? {
        let screens = externalScreens()
        if let selectedDisplayID,
           let screen = screens.first(where: { Self.displayID(for: $0) == selectedDisplayID }) {
            return screen
        }

        selectedDisplayID = screens.compactMap { Self.displayID(for: $0) }.first
        return screens.first
    }

    private func externalScreens() -> [NSScreen] {
        let primaryID = Self.displayID(for: primaryScreen())
        return NSScreen.screens.filter { Self.displayID(for: $0) != primaryID }
    }

    private func primaryScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens.first!
    }

    @objc private func screenParametersChanged() {
        if fullscreenEnabled && selectedExternalScreen() == nil {
            fullscreenEnabled = false
        }
        rebuildWindow()
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    private static func label(for screen: NSScreen, id: CGDirectDisplayID) -> String {
        let frame = screen.frame
        return "Display \(id)  \(Int(frame.width))x\(Int(frame.height))"
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
