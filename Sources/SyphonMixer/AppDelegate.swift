import AppKit
import Metal
import Syphon
import SyphonMixerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: MixerEngine?
    private var controlPanel: ControlPanelController?
    private var outputController: OutputWindowController?
    private var controlWindow: NSWindow?
    private var refreshTimer: Timer?
    private var knownServers: [SyphonServerInfo] = []
    private var selectedServerIDs = Array<String?>(repeating: nil, count: MixerEngine.syphonInputCount)

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        setupMenu()

        guard let device = MTLCreateSystemDefaultDevice() else {
            presentFatalError("Metal device is unavailable.")
            return
        }

        do {
            let engine = try MixerEngine(device: device)
            let outputView = engine.makeOutputView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
            let outputController = OutputWindowController(outputView: outputView)
            let previewWidth: CGFloat = MixerEngine.channelCount > 4 ? 176 : 220
            let previewHeight = previewWidth * 9.0 / 16.0
            let channelPreviewViews: [NSView] = (0..<MixerEngine.channelCount).map { index in
                engine.makeChannelPreviewView(
                    channel: index,
                    frame: NSRect(x: 0, y: 0, width: previewWidth, height: previewHeight)
                ) as NSView
            }
            let controlPanel = ControlPanelController(channelPreviewViews: channelPreviewViews)

            self.engine = engine
            self.outputController = outputController
            self.controlPanel = controlPanel
            outputController.onScreensChanged = { [weak self] in
                self?.refreshDisplayOptions()
            }

            wireControlPanel(controlPanel)
            showControlWindow(controlPanel.view)
            refreshDisplayOptions()
            refreshServers()
            startRefreshTimer()
        } catch {
            presentFatalError(error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func wireControlPanel(_ panel: ControlPanelController) {
        panel.onRefreshServers = { [weak self] in
            self?.refreshServers()
        }
        panel.onChannelSourceChanged = { [weak self] index, id in
            self?.setChannelSource(index: index, id: id)
        }
        panel.onChannelEnabledChanged = { [weak self] index, enabled in
            self?.engine?.setEnabled(channel: index, enabled: enabled)
            self?.refreshChannelStatuses()
        }
        panel.onChannelVolumeChanged = { [weak self] index, value in
            self?.engine?.setVolume(channel: index, value: value)
        }
        panel.onChannelScaleModeChanged = { [weak self] index, mode in
            self?.engine?.setScaleMode(channel: index, mode: mode)
        }
        panel.onOutputSizeChanged = { [weak self] width, height in
            guard let self else { return }
            engine?.setOutputSize(width: width, height: height)
            panel.updateOutputLabel(engine?.outputSizeLabel() ?? "\(width)x\(height)")
        }
        panel.onPixelMapChanged = { [weak self] enabled in
            self?.engine?.setPixelMapEnabled(enabled)
        }
        panel.onDisplayChanged = { [weak self] id in
            self?.outputController?.setSelectedDisplayID(id)
            self?.refreshDisplayOptions()
        }
        panel.onFullscreenChanged = { [weak self] enabled in
            guard let self else { return }
            outputController?.setFullscreenEnabled(enabled)
            panel.setFullscreenState(outputController?.isFullscreenEnabled ?? false)
            refreshDisplayOptions()
        }
        panel.onQuit = {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showControlWindow(_ contentView: NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "syphon-mixer"
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        controlWindow = window
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.refreshServers()
            self?.refreshChannelStatuses()
        }
    }

    private func refreshServers() {
        let descriptions = SyphonServerDirectory.shared().servers.map { $0 as [String: Any] }
        knownServers = descriptions.compactMap { description in
            guard let info = SyphonServerFormatter.info(from: description),
                  info.serverName != MixerEngine.outputServerName else {
                return nil
            }
            return info
        }

        for index in selectedServerIDs.indices {
            if let selectedID = selectedServerIDs[index],
               !knownServers.contains(where: { $0.id == selectedID }) {
                selectedServerIDs[index] = nil
                engine?.setSource(channel: index, source: nil)
            }
        }

        controlPanel?.updateServers(knownServers, selectedIDs: selectedServerIDs)
        refreshChannelStatuses()
    }

    private func refreshDisplayOptions() {
        guard let outputController else { return }
        controlPanel?.updateDisplayOptions(
            outputController.displayOptions(),
            selectedID: outputController.currentSelectedDisplayID,
            canFullscreen: outputController.canFullscreen,
            status: outputController.displayStatus()
        )
        controlPanel?.setFullscreenState(outputController.isFullscreenEnabled)
    }

    private func refreshChannelStatuses() {
        controlPanel?.updateChannelStatuses(engine?.channelStatuses() ?? [])
    }

    private func setChannelSource(index: Int, id: String?) {
        guard selectedServerIDs.indices.contains(index) else { return }
        selectedServerIDs[index] = id
        let source = id.flatMap { selectedID in
            knownServers.first(where: { $0.id == selectedID })
        }
        engine?.setSource(channel: index, source: source)
        refreshChannelStatuses()
    }

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "Quit syphon-mixer",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func presentFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "syphon-mixer could not start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
