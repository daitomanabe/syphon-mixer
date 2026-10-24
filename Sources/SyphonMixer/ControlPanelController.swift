import AppKit
import CoreGraphics
import SyphonMixerCore

final class ControlPanelController: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 640))

    var onRefreshServers: (() -> Void)?
    var onChannelSourceChanged: ((Int, String?) -> Void)?
    var onChannelEnabledChanged: ((Int, Bool) -> Void)?
    var onChannelVolumeChanged: ((Int, Float) -> Void)?
    var onChannelScaleModeChanged: ((Int, ScaleMode) -> Void)?
    var onOutputSizeChanged: ((Int, Int) -> Void)?
    var onPixelMapChanged: ((Bool) -> Void)?
    var onOutputFlipChanged: ((Bool, Bool) -> Void)?
    var onDisplayChanged: ((CGDirectDisplayID?) -> Void)?
    var onFullscreenChanged: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    private var serverPopUps: [NSPopUpButton] = []
    private var enabledButtons: [NSButton] = []
    private var volumeSliders: [NSSlider] = []
    private var volumeLabels: [NSTextField] = []
    private var modePopUps: [NSPopUpButton] = []
    private var statusLabels: [NSTextField] = []
    private let widthField = NSTextField(string: "1920")
    private let heightField = NSTextField(string: "1080")
    private let outputLabel = NSTextField(labelWithString: "Output: 1920x1080")
    private let displayPopUp = NSPopUpButton()
    private let pixelMapButton = NSButton(checkboxWithTitle: "PixelMap", target: nil, action: nil)
    private let flipXButton = NSButton(checkboxWithTitle: "Flip X", target: nil, action: nil)
    private let flipYButton = NSButton(checkboxWithTitle: "Flip Y", target: nil, action: nil)
    private let fullscreenButton = NSButton(checkboxWithTitle: "Fullscreen", target: nil, action: nil)
    private let displayStatusLabel = NSTextField(labelWithString: "main preview, no external display")
    private let channelPreviewViews: [NSView]
    private var isUpdating = false

    init(channelPreviewViews: [NSView]) {
        self.channelPreviewViews = channelPreviewViews
        super.init()
        buildUI()
    }

    func updateServers(_ servers: [SyphonServerInfo], selectedIDs: [String?]) {
        isUpdating = true
        for index in serverPopUps.indices {
            let popUp = serverPopUps[index]
            let selectedID = selectedIDs.indices.contains(index) ? selectedIDs[index] : nil
            popUp.removeAllItems()
            popUp.addItem(withTitle: "None")
            popUp.item(at: 0)?.representedObject = nil

            for server in servers {
                popUp.addItem(withTitle: server.displayName)
                popUp.lastItem?.representedObject = server.id
            }

            if let selectedID,
               let item = popUp.itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
                popUp.select(item)
            } else {
                popUp.selectItem(at: 0)
            }
        }
        isUpdating = false
    }

    func updateDisplayOptions(
        _ options: [(id: CGDirectDisplayID, label: String)],
        selectedID: CGDirectDisplayID?,
        canFullscreen: Bool,
        status: String
    ) {
        isUpdating = true
        displayPopUp.removeAllItems()
        if options.isEmpty {
            displayPopUp.addItem(withTitle: "Preview only")
            displayPopUp.item(at: 0)?.representedObject = nil
            displayPopUp.isEnabled = false
        } else {
            for option in options {
                displayPopUp.addItem(withTitle: option.label)
                displayPopUp.lastItem?.representedObject = NSNumber(value: option.id)
            }
            displayPopUp.isEnabled = true
        }

        if let selectedID,
           let item = displayPopUp.itemArray.first(where: { ($0.representedObject as? NSNumber)?.uint32Value == selectedID }) {
            displayPopUp.select(item)
        } else {
            displayPopUp.selectItem(at: 0)
        }
        fullscreenButton.isEnabled = true
        displayStatusLabel.stringValue = status
        isUpdating = false
    }

    func updateOutputLabel(_ value: String) {
        outputLabel.stringValue = "Output: \(value)"
    }

    func updateChannelStatuses(_ statuses: [String]) {
        for index in statusLabels.indices {
            let fallback = "\(channelTitle(index: index)): none"
            statusLabels[index].stringValue = statuses.indices.contains(index) ? statuses[index] : fallback
        }
    }

    func setFullscreenState(_ enabled: Bool) {
        fullscreenButton.state = enabled ? .on : .off
    }

    private func buildUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14.0
        root.translatesAutoresizingMaskIntoConstraints = false
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let title = NSTextField(labelWithString: "syphon-mixer")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(title)

        let outputRow = NSStackView()
        outputRow.orientation = .horizontal
        outputRow.alignment = .centerY
        outputRow.spacing = 10.0
        outputRow.addArrangedSubview(outputLabel)
        outputRow.addArrangedSubview(label("W"))
        outputRow.addArrangedSubview(widthField)
        outputRow.addArrangedSubview(label("H"))
        outputRow.addArrangedSubview(heightField)

        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyOutputSize))
        outputRow.addArrangedSubview(applyButton)
        pixelMapButton.state = .off
        pixelMapButton.target = self
        pixelMapButton.action = #selector(pixelMapChanged)
        outputRow.addArrangedSubview(pixelMapButton)
        outputRow.addArrangedSubview(displayPopUp)
        fullscreenButton.target = self
        fullscreenButton.action = #selector(fullscreenChanged)
        outputRow.addArrangedSubview(fullscreenButton)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshServers))
        outputRow.addArrangedSubview(refreshButton)
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quit))
        outputRow.addArrangedSubview(quitButton)
        root.addArrangedSubview(outputRow)

        let flipRow = NSStackView()
        flipRow.orientation = .horizontal
        flipRow.alignment = .centerY
        flipRow.spacing = 10.0
        flipRow.addArrangedSubview(label("Output Flip"))
        for button in [flipXButton, flipYButton] {
            button.state = .off
            button.target = self
            button.action = #selector(outputFlipChanged)
            flipRow.addArrangedSubview(button)
        }
        root.addArrangedSubview(flipRow)

        widthField.widthAnchor.constraint(equalToConstant: 68).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 68).isActive = true
        displayPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        displayPopUp.target = self
        displayPopUp.action = #selector(displayChanged)
        displayStatusLabel.lineBreakMode = .byTruncatingTail
        displayStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 900).isActive = true
        root.addArrangedSubview(displayStatusLabel)

        for index in 0..<MixerEngine.channelCount {
            root.addArrangedSubview(makeChannelRow(index: index))
        }

        root.addArrangedSubview(makePreviewGrid())
    }

    private func makeChannelRow(index: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10.0
        let isTestPattern = isTestPatternChannel(index)

        let channelLabel = label(channelTitle(index: index))
        channelLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(channelLabel)

        let enabledButton = NSButton(checkboxWithTitle: "On", target: self, action: #selector(enabledChanged))
        enabledButton.state = isTestPattern ? .off : .on
        enabledButton.tag = index
        enabledButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        enabledButtons.append(enabledButton)
        row.addArrangedSubview(enabledButton)

        if isTestPattern {
            let sourceLabel = NSTextField(labelWithString: "Built-in Test Pattern")
            sourceLabel.lineBreakMode = .byTruncatingTail
            sourceLabel.widthAnchor.constraint(equalToConstant: 250).isActive = true
            row.addArrangedSubview(sourceLabel)
        } else {
            let serverPopUp = NSPopUpButton()
            serverPopUp.target = self
            serverPopUp.action = #selector(serverChanged)
            serverPopUp.tag = index
            serverPopUp.widthAnchor.constraint(equalToConstant: 250).isActive = true
            serverPopUps.append(serverPopUp)
            row.addArrangedSubview(serverPopUp)
        }

        let slider = NSSlider(value: 1.0, minValue: 0.0, maxValue: 1.0, target: self, action: #selector(volumeChanged))
        slider.tag = index
        slider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        volumeSliders.append(slider)
        row.addArrangedSubview(slider)

        let volumeLabel = NSTextField(labelWithString: "100%")
        volumeLabel.alignment = .right
        volumeLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true
        volumeLabels.append(volumeLabel)
        row.addArrangedSubview(volumeLabel)

        if isTestPattern {
            let modeLabel = NSTextField(labelWithString: "Stretch")
            modeLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
            row.addArrangedSubview(modeLabel)
        } else {
            let modePopUp = NSPopUpButton()
            for mode in ScaleMode.allCases {
                modePopUp.addItem(withTitle: mode.rawValue)
                modePopUp.lastItem?.representedObject = mode.rawValue
            }
            modePopUp.target = self
            modePopUp.action = #selector(scaleModeChanged)
            modePopUp.tag = index
            modePopUp.widthAnchor.constraint(equalToConstant: 120).isActive = true
            modePopUps.append(modePopUp)
            row.addArrangedSubview(modePopUp)
        }

        let status = NSTextField(labelWithString: isTestPattern ? "TEST: off" : "CH\(index + 1): none")
        status.lineBreakMode = .byTruncatingTail
        status.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        statusLabels.append(status)
        row.addArrangedSubview(status)

        return row
    }

    private func makePreviewGrid() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12.0
        let previewWidth: CGFloat = MixerEngine.channelCount > 4 ? 176 : 220
        let previewHeight = previewWidth * 9.0 / 16.0

        for index in 0..<MixerEngine.channelCount {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 6.0

            let title = label("Preview \(channelTitle(index: index))")
            column.addArrangedSubview(title)

            let preview = channelPreviewViews.indices.contains(index) ? channelPreviewViews[index] : NSView()
            preview.wantsLayer = true
            preview.layer?.backgroundColor = NSColor.black.cgColor
            preview.layer?.borderColor = NSColor.separatorColor.cgColor
            preview.layer?.borderWidth = 1.0
            preview.widthAnchor.constraint(equalToConstant: previewWidth).isActive = true
            preview.heightAnchor.constraint(equalToConstant: previewHeight).isActive = true
            column.addArrangedSubview(preview)

            row.addArrangedSubview(column)
        }

        return row
    }

    private func label(_ string: String) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = .systemFont(ofSize: 13, weight: .medium)
        return field
    }

    private func channelTitle(index: Int) -> String {
        isTestPatternChannel(index) ? "TEST" : "CH\(index + 1)"
    }

    private func isTestPatternChannel(_ index: Int) -> Bool {
        index == MixerEngine.testPatternChannelIndex
    }

    @objc private func refreshServers() {
        onRefreshServers?()
    }

    @objc private func serverChanged(_ sender: NSPopUpButton) {
        guard !isUpdating else { return }
        onChannelSourceChanged?(sender.tag, sender.selectedItem?.representedObject as? String)
    }

    @objc private func enabledChanged(_ sender: NSButton) {
        guard !isUpdating else { return }
        onChannelEnabledChanged?(sender.tag, sender.state == .on)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue)
        if volumeLabels.indices.contains(sender.tag) {
            volumeLabels[sender.tag].stringValue = "\(Int(round(value * 100.0)))%"
        }
        onChannelVolumeChanged?(sender.tag, value)
    }

    @objc private func scaleModeChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = ScaleMode(rawValue: rawValue) else {
            return
        }
        onChannelScaleModeChanged?(sender.tag, mode)
    }

    @objc private func applyOutputSize() {
        onOutputSizeChanged?(widthField.integerValue, heightField.integerValue)
    }

    @objc private func pixelMapChanged(_ sender: NSButton) {
        guard !isUpdating else { return }
        onPixelMapChanged?(sender.state == .on)
    }

    @objc private func outputFlipChanged() {
        guard !isUpdating else { return }
        onOutputFlipChanged?(flipXButton.state == .on, flipYButton.state == .on)
    }

    @objc private func displayChanged() {
        guard !isUpdating else { return }
        let number = displayPopUp.selectedItem?.representedObject as? NSNumber
        onDisplayChanged?(number.map { CGDirectDisplayID($0.uint32Value) })
    }

    @objc private func fullscreenChanged() {
        onFullscreenChanged?(fullscreenButton.state == .on)
    }

    @objc private func quit() {
        onQuit?()
    }
}
