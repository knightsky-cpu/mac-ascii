import AppKit
import MetalKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let opacitySelectionValues: [Float] = stride(from: 0.10 as Float, through: 1.00 as Float, by: 0.05).map { $0 }
    private static let brightnessSelectionValues: [Float] = [
        -0.50, -0.40, -0.30, -0.20, -0.10, -0.05,
        0.00, 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50,
    ]
    private static let contrastSelectionValues: [Float] = [
        0.50, 0.65, 0.80, 0.90, 1.00, 1.10, 1.20, 1.35, 1.50, 1.75, 2.00,
    ]
    private static let gammaSelectionValues: [Float] = [
        0.50, 0.60, 0.70, 0.80, 0.90, 1.00, 1.20, 1.40, 1.60, 1.80, 2.00,
    ]
    private static let edgeSelectionValues: [Float] = [
        0.00, 0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75, 2.00,
    ]

    private let state = AppState()
    private var metalView: MTKView?
    private var window: OverlayWindow?
    private var renderer: Renderer?
    private var captureManager: ScreenCaptureManager?
    private var hotkeyManager: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var gridMenuItem: NSMenuItem?
    private var styleMenuItem: NSMenuItem?
    private var renderModeMenuItem: NSMenuItem?
    private var luminanceMenuItem: NSMenuItem?
    private var frameRateMenuItem: NSMenuItem?
    private var opacityMenuItem: NSMenuItem?
    private var toneMenuItem: NSMenuItem?
    private var edgeMenuItem: NSMenuItem?
    private var windowLevelMenuItem: NSMenuItem?
    private var gridSelectionMenu: NSMenu?
    private var styleSelectionMenu: NSMenu?
    private var renderModeSelectionMenu: NSMenu?
    private var luminanceSelectionMenu: NSMenu?
    private var frameRateSelectionMenu: NSMenu?
    private var opacitySelectionMenu: NSMenu?
    private var brightnessSelectionMenu: NSMenu?
    private var contrastSelectionMenu: NSMenu?
    private var gammaSelectionMenu: NSMenu?
    private var edgeSelectionMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        guard let screen = NSScreen.main else {
            print("MacAscii: no main screen")
            NSApp.terminate(nil)
            return
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("MacAscii: Metal device unavailable")
            NSApp.terminate(nil)
            return
        }

        let maximumFPS = screen.maximumFramesPerSecond
        state.configureSupportedFrameRates(maximumFPS: maximumFPS)

        let metalView = MTKView(frame: screen.frame, device: device)
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = state.frameRate
        self.metalView = metalView
        print(
            "MacAscii: screen frame=\(Int(screen.frame.width))x\(Int(screen.frame.height)) " +
            "scale=\(screen.backingScaleFactor) " +
            "max-fps=\(maximumFPS)"
        )

        guard let renderer = Renderer(
            device: device,
            colorPixelFormat: metalView.colorPixelFormat,
            state: state,
            displayScale: screen.backingScaleFactor
        ) else {
            print("MacAscii: renderer unavailable")
            NSApp.terminate(nil)
            return
        }

        metalView.delegate = renderer
        self.renderer = renderer

        let window = OverlayWindow(screen: screen, metalView: metalView)
        self.window = window
        if state.overlayVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
        logAppRenderState(reason: "startup")

        captureManager = ScreenCaptureManager { [weak renderer] pixelBuffer in
            renderer?.update(pixelBuffer: pixelBuffer)
        }

        Task {
            await captureManager?.start()
        }

        hotkeyManager = HotkeyManager { [weak self] command in
            DispatchQueue.main.async {
                self?.handle(command: command)
            }
        }
        hotkeyManager?.start()
        configureStatusMenu()

        state.logState("started")
        print("MacAscii: hotkeys Ctrl+Option+A toggle, Ctrl+Option+. grid, Ctrl+Option+' style, Ctrl+Option+M render mode, Ctrl+Option+F fps, Ctrl+Option+, luminance, Ctrl+Option+- opacity down, Ctrl+Option+= opacity up, Ctrl+Option+B brightness, Ctrl+Option+C contrast, Ctrl+Option+G gamma, Ctrl+Option+E edge")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        Task {
            await captureManager?.stop()
        }
    }

    private func configureStatusMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MacAscii"
        statusItem.button?.toolTip = "MacAscii desktop overlay"

        let menu = NSMenu()
        menu.delegate = self
        let titleItem = NSMenuItem(title: "MacAscii", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let toggleMenuItem = NSMenuItem(
            title: "Toggle Overlay",
            action: #selector(toggleOverlayFromMenu),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        let cycleGridItem = NSMenuItem(
            title: "Cycle Grid Size",
            action: #selector(cycleGridFromMenu),
            keyEquivalent: ""
        )
        cycleGridItem.target = self
        menu.addItem(cycleGridItem)

        let selectGridItem = NSMenuItem(title: "Select Grid", action: nil, keyEquivalent: "")
        let gridSelectionMenu = NSMenu(title: "Select Grid")
        for (index, preset) in state.gridPresets.enumerated() {
            let item = NSMenuItem(
                title: "\(preset.name) (\(gridCellSizeLabel(for: preset.cellSize)))",
                action: #selector(selectGridFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            gridSelectionMenu.addItem(item)
        }
        menu.setSubmenu(gridSelectionMenu, for: selectGridItem)
        menu.addItem(selectGridItem)

        let cycleStyleItem = NSMenuItem(
            title: "Cycle Style",
            action: #selector(cycleStyleFromMenu),
            keyEquivalent: ""
        )
        cycleStyleItem.target = self
        menu.addItem(cycleStyleItem)

        let selectStyleItem = NSMenuItem(title: "Select Style", action: nil, keyEquivalent: "")
        let styleSelectionMenu = NSMenu(title: "Select Style")
        for (index, style) in state.visualStyles.enumerated() {
            let item = NSMenuItem(title: style.name, action: #selector(selectStyleFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            styleSelectionMenu.addItem(item)
        }
        menu.setSubmenu(styleSelectionMenu, for: selectStyleItem)
        menu.addItem(selectStyleItem)

        let cycleRenderModeItem = NSMenuItem(
            title: "Cycle Render Mode",
            action: #selector(cycleRenderModeFromMenu),
            keyEquivalent: ""
        )
        cycleRenderModeItem.target = self
        menu.addItem(cycleRenderModeItem)

        let selectRenderModeItem = NSMenuItem(title: "Select Render Mode", action: nil, keyEquivalent: "")
        let renderModeSelectionMenu = NSMenu(title: "Select Render Mode")
        for mode in RenderMode.allCases {
            let item = NSMenuItem(title: mode.name, action: #selector(selectRenderModeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(mode.mode)
            renderModeSelectionMenu.addItem(item)
        }
        menu.setSubmenu(renderModeSelectionMenu, for: selectRenderModeItem)
        menu.addItem(selectRenderModeItem)

        let toggleLuminanceItem = NSMenuItem(
            title: "Toggle 10/20 Luminance",
            action: #selector(toggleLuminanceFromMenu),
            keyEquivalent: ""
        )
        toggleLuminanceItem.target = self
        menu.addItem(toggleLuminanceItem)

        let selectLuminanceItem = NSMenuItem(title: "Select Luminance", action: nil, keyEquivalent: "")
        let luminanceSelectionMenu = NSMenu(title: "Select Luminance")
        for mode in LuminanceMode.allCases {
            let item = NSMenuItem(
                title: "\(mode.bucketCount) buckets",
                action: #selector(selectLuminanceFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = mode.bucketCount
            luminanceSelectionMenu.addItem(item)
        }
        menu.setSubmenu(luminanceSelectionMenu, for: selectLuminanceItem)
        menu.addItem(selectLuminanceItem)

        let cycleFrameRateItem = NSMenuItem(
            title: "Cycle FPS",
            action: #selector(cycleFrameRateFromMenu),
            keyEquivalent: ""
        )
        cycleFrameRateItem.target = self
        menu.addItem(cycleFrameRateItem)

        let selectFrameRateItem = NSMenuItem(title: "Select FPS", action: nil, keyEquivalent: "")
        let frameRateSelectionMenu = NSMenu(title: "Select FPS")
        menu.setSubmenu(frameRateSelectionMenu, for: selectFrameRateItem)
        menu.addItem(selectFrameRateItem)

        let opacityDownItem = NSMenuItem(
            title: "Opacity Down",
            action: #selector(opacityDownFromMenu),
            keyEquivalent: ""
        )
        opacityDownItem.target = self
        menu.addItem(opacityDownItem)

        let opacityUpItem = NSMenuItem(
            title: "Opacity Up",
            action: #selector(opacityUpFromMenu),
            keyEquivalent: ""
        )
        opacityUpItem.target = self
        menu.addItem(opacityUpItem)

        let selectOpacityItem = NSMenuItem(title: "Select Opacity", action: nil, keyEquivalent: "")
        let opacitySelectionMenu = NSMenu(title: "Select Opacity")
        for value in Self.opacitySelectionValues {
            let item = makeFloatSelectionItem(
                title: "\(Int(round(value * 100)))%",
                value: value,
                action: #selector(selectOpacityFromMenu(_:))
            )
            opacitySelectionMenu.addItem(item)
        }
        menu.setSubmenu(opacitySelectionMenu, for: selectOpacityItem)
        menu.addItem(selectOpacityItem)

        menu.addItem(.separator())

        let brightnessDownItem = NSMenuItem(
            title: "Brightness Down",
            action: #selector(brightnessDownFromMenu),
            keyEquivalent: ""
        )
        brightnessDownItem.target = self
        menu.addItem(brightnessDownItem)

        let brightnessUpItem = NSMenuItem(
            title: "Brightness Up",
            action: #selector(brightnessUpFromMenu),
            keyEquivalent: ""
        )
        brightnessUpItem.target = self
        menu.addItem(brightnessUpItem)

        let selectBrightnessItem = NSMenuItem(title: "Select Brightness", action: nil, keyEquivalent: "")
        let brightnessSelectionMenu = NSMenu(title: "Select Brightness")
        for value in Self.brightnessSelectionValues {
            let item = makeFloatSelectionItem(
                title: String(format: "%.2f", value),
                value: value,
                action: #selector(selectBrightnessFromMenu(_:))
            )
            brightnessSelectionMenu.addItem(item)
        }
        menu.setSubmenu(brightnessSelectionMenu, for: selectBrightnessItem)
        menu.addItem(selectBrightnessItem)

        let contrastDownItem = NSMenuItem(
            title: "Contrast Down",
            action: #selector(contrastDownFromMenu),
            keyEquivalent: ""
        )
        contrastDownItem.target = self
        menu.addItem(contrastDownItem)

        let contrastUpItem = NSMenuItem(
            title: "Contrast Up",
            action: #selector(contrastUpFromMenu),
            keyEquivalent: ""
        )
        contrastUpItem.target = self
        menu.addItem(contrastUpItem)

        let selectContrastItem = NSMenuItem(title: "Select Contrast", action: nil, keyEquivalent: "")
        let contrastSelectionMenu = NSMenu(title: "Select Contrast")
        for value in Self.contrastSelectionValues {
            let item = makeFloatSelectionItem(
                title: String(format: "%.2f", value),
                value: value,
                action: #selector(selectContrastFromMenu(_:))
            )
            contrastSelectionMenu.addItem(item)
        }
        menu.setSubmenu(contrastSelectionMenu, for: selectContrastItem)
        menu.addItem(selectContrastItem)

        let gammaDownItem = NSMenuItem(
            title: "Gamma Down",
            action: #selector(gammaDownFromMenu),
            keyEquivalent: ""
        )
        gammaDownItem.target = self
        menu.addItem(gammaDownItem)

        let gammaUpItem = NSMenuItem(
            title: "Gamma Up",
            action: #selector(gammaUpFromMenu),
            keyEquivalent: ""
        )
        gammaUpItem.target = self
        menu.addItem(gammaUpItem)

        let selectGammaItem = NSMenuItem(title: "Select Gamma", action: nil, keyEquivalent: "")
        let gammaSelectionMenu = NSMenu(title: "Select Gamma")
        for value in Self.gammaSelectionValues {
            let item = makeFloatSelectionItem(
                title: String(format: "%.2f", value),
                value: value,
                action: #selector(selectGammaFromMenu(_:))
            )
            gammaSelectionMenu.addItem(item)
        }
        menu.setSubmenu(gammaSelectionMenu, for: selectGammaItem)
        menu.addItem(selectGammaItem)

        menu.addItem(.separator())

        let edgeDownItem = NSMenuItem(
            title: "Edge Down",
            action: #selector(edgeDownFromMenu),
            keyEquivalent: ""
        )
        edgeDownItem.target = self
        menu.addItem(edgeDownItem)

        let edgeUpItem = NSMenuItem(
            title: "Edge Up",
            action: #selector(edgeUpFromMenu),
            keyEquivalent: ""
        )
        edgeUpItem.target = self
        menu.addItem(edgeUpItem)

        let selectEdgeItem = NSMenuItem(title: "Select Edge Strength", action: nil, keyEquivalent: "")
        let edgeSelectionMenu = NSMenu(title: "Select Edge Strength")
        for value in Self.edgeSelectionValues {
            let item = makeFloatSelectionItem(
                title: String(format: "%.2f", value),
                value: value,
                action: #selector(selectEdgeFromMenu(_:))
            )
            edgeSelectionMenu.addItem(item)
        }
        menu.setSubmenu(edgeSelectionMenu, for: selectEdgeItem)
        menu.addItem(selectEdgeItem)

        menu.addItem(.separator())

        let resetItem = NSMenuItem(
            title: "Reset Visual Defaults",
            action: #selector(resetVisualDefaultsFromMenu),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let gridMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        gridMenuItem.isEnabled = false
        menu.addItem(gridMenuItem)

        let styleMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        styleMenuItem.isEnabled = false
        menu.addItem(styleMenuItem)

        let renderModeMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        renderModeMenuItem.isEnabled = false
        menu.addItem(renderModeMenuItem)

        let luminanceMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        luminanceMenuItem.isEnabled = false
        menu.addItem(luminanceMenuItem)

        let frameRateMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        frameRateMenuItem.isEnabled = false
        menu.addItem(frameRateMenuItem)

        let opacityMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        opacityMenuItem.isEnabled = false
        menu.addItem(opacityMenuItem)

        let toneMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        toneMenuItem.isEnabled = false
        menu.addItem(toneMenuItem)

        let edgeMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        edgeMenuItem.isEnabled = false
        menu.addItem(edgeMenuItem)

        let windowLevelMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        windowLevelMenuItem.isEnabled = false
        menu.addItem(windowLevelMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MacAscii", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.toggleMenuItem = toggleMenuItem
        self.gridMenuItem = gridMenuItem
        self.styleMenuItem = styleMenuItem
        self.renderModeMenuItem = renderModeMenuItem
        self.luminanceMenuItem = luminanceMenuItem
        self.frameRateMenuItem = frameRateMenuItem
        self.opacityMenuItem = opacityMenuItem
        self.toneMenuItem = toneMenuItem
        self.edgeMenuItem = edgeMenuItem
        self.windowLevelMenuItem = windowLevelMenuItem
        self.gridSelectionMenu = gridSelectionMenu
        self.styleSelectionMenu = styleSelectionMenu
        self.renderModeSelectionMenu = renderModeSelectionMenu
        self.luminanceSelectionMenu = luminanceSelectionMenu
        self.frameRateSelectionMenu = frameRateSelectionMenu
        self.opacitySelectionMenu = opacitySelectionMenu
        self.brightnessSelectionMenu = brightnessSelectionMenu
        self.contrastSelectionMenu = contrastSelectionMenu
        self.gammaSelectionMenu = gammaSelectionMenu
        self.edgeSelectionMenu = edgeSelectionMenu
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        toggleMenuItem?.title = state.overlayVisible ? "Hide Overlay" : "Show Overlay"
        gridMenuItem?.title = "Grid: \(state.activeGrid.name) (\(gridCellSizeLabel(for: state.activeGrid.cellSize)))"
        styleMenuItem?.title = "Style: \(state.activeStyle.name)"
        renderModeMenuItem?.title = "Render: \(state.renderMode.name)"
        luminanceMenuItem?.title = "Luminance: \(state.luminanceMode.bucketCount) buckets"
        frameRateMenuItem?.title = "FPS: \(state.frameRate)"
        opacityMenuItem?.title = "Opacity: \(Int(state.overlayOpacity * 100))%"
        toneMenuItem?.title = String(
            format: "Tone: B %.2f  C %.2f  G %.2f",
            state.brightness,
            state.contrast,
            state.gamma
        )
        edgeMenuItem?.title = String(format: "Edge: %.2f", state.edgeStrength)
        windowLevelMenuItem?.title = "Window level: \(window?.levelDescription ?? "unavailable")"
        refreshSelectionMenus()
    }

    @objc private func toggleOverlayFromMenu() {
        handle(command: .toggleOverlay)
    }

    @objc private func cycleGridFromMenu() {
        handle(command: .cycleGrid)
    }

    @objc private func selectGridFromMenu(_ sender: NSMenuItem) {
        state.setGridIndex(sender.tag)
        finishStateChange(hudMessage: "Grid: \(state.activeGrid.name) (\(gridCellSizeLabel(for: state.activeGrid.cellSize)))")
    }

    @objc private func cycleStyleFromMenu() {
        handle(command: .cycleStyle)
    }

    @objc private func selectStyleFromMenu(_ sender: NSMenuItem) {
        state.setStyleIndex(sender.tag)
        finishStateChange(hudMessage: "Style: \(state.activeStyle.name)")
    }

    @objc private func cycleRenderModeFromMenu() {
        handle(command: .cycleRenderMode)
    }

    @objc private func selectRenderModeFromMenu(_ sender: NSMenuItem) {
        guard let mode = RenderMode.allCases.first(where: { Int($0.mode) == sender.tag }) else {
            return
        }
        state.setRenderMode(mode)
        finishStateChange(hudMessage: "Render: \(state.renderMode.name)")
    }

    @objc private func toggleLuminanceFromMenu() {
        handle(command: .toggleLuminance)
    }

    @objc private func selectLuminanceFromMenu(_ sender: NSMenuItem) {
        guard let mode = LuminanceMode.allCases.first(where: { $0.bucketCount == sender.tag }) else {
            return
        }
        state.setLuminanceMode(mode)
        finishStateChange(hudMessage: "Luminance: \(state.luminanceMode.bucketCount) buckets")
    }

    @objc private func cycleFrameRateFromMenu() {
        handle(command: .cycleFrameRate)
    }

    @objc private func selectFrameRateFromMenu(_ sender: NSMenuItem) {
        state.setFrameRate(sender.tag)
        finishStateChange(hudMessage: "FPS: \(state.frameRate)")
    }

    @objc private func opacityDownFromMenu() {
        handle(command: .decreaseOpacity)
    }

    @objc private func opacityUpFromMenu() {
        handle(command: .increaseOpacity)
    }

    @objc private func selectOpacityFromMenu(_ sender: NSMenuItem) {
        guard let value = floatValue(from: sender) else {
            return
        }
        state.setOverlayOpacity(value)
        finishStateChange(hudMessage: "Opacity: \(Int(state.overlayOpacity * 100))%")
    }

    @objc private func brightnessDownFromMenu() {
        state.decreaseBrightness()
        finishStateChange(hudMessage: String(format: "Brightness: %.2f", state.brightness))
    }

    @objc private func brightnessUpFromMenu() {
        state.increaseBrightness()
        finishStateChange(hudMessage: String(format: "Brightness: %.2f", state.brightness))
    }

    @objc private func selectBrightnessFromMenu(_ sender: NSMenuItem) {
        guard let value = floatValue(from: sender) else {
            return
        }
        state.setBrightness(value)
        finishStateChange(hudMessage: String(format: "Brightness: %.2f", state.brightness))
    }

    @objc private func contrastDownFromMenu() {
        state.decreaseContrast()
        finishStateChange(hudMessage: String(format: "Contrast: %.2f", state.contrast))
    }

    @objc private func contrastUpFromMenu() {
        state.increaseContrast()
        finishStateChange(hudMessage: String(format: "Contrast: %.2f", state.contrast))
    }

    @objc private func selectContrastFromMenu(_ sender: NSMenuItem) {
        guard let value = floatValue(from: sender) else {
            return
        }
        state.setContrast(value)
        finishStateChange(hudMessage: String(format: "Contrast: %.2f", state.contrast))
    }

    @objc private func gammaDownFromMenu() {
        state.decreaseGamma()
        finishStateChange(hudMessage: String(format: "Gamma: %.2f", state.gamma))
    }

    @objc private func gammaUpFromMenu() {
        state.increaseGamma()
        finishStateChange(hudMessage: String(format: "Gamma: %.2f", state.gamma))
    }

    @objc private func selectGammaFromMenu(_ sender: NSMenuItem) {
        guard let value = floatValue(from: sender) else {
            return
        }
        state.setGamma(value)
        finishStateChange(hudMessage: String(format: "Gamma: %.2f", state.gamma))
    }

    @objc private func edgeDownFromMenu() {
        state.decreaseEdgeStrength()
        finishStateChange(hudMessage: String(format: "Edge: %.2f", state.edgeStrength))
    }

    @objc private func edgeUpFromMenu() {
        state.increaseEdgeStrength()
        finishStateChange(hudMessage: String(format: "Edge: %.2f", state.edgeStrength))
    }

    @objc private func selectEdgeFromMenu(_ sender: NSMenuItem) {
        guard let value = floatValue(from: sender) else {
            return
        }
        state.setEdgeStrength(value)
        finishStateChange(hudMessage: String(format: "Edge: %.2f", state.edgeStrength))
    }

    @objc private func resetVisualDefaultsFromMenu() {
        state.resetVisualDefaults()
        finishStateChange(hudMessage: "Reset visual defaults")
        logAppRenderState(reason: "reset-menu")
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func handle(command: HotkeyManager.Command) {
        switch command {
        case .toggleOverlay:
            state.toggleOverlay()
        case .cycleGrid:
            state.cycleGrid()
        case .cycleStyle:
            state.cycleStyle()
        case .cycleRenderMode:
            state.cycleRenderMode()
        case .toggleLuminance:
            state.toggleLuminanceMode()
        case .cycleFrameRate:
            state.cycleFrameRate()
        case .decreaseOpacity:
            state.decreaseOpacity()
        case .increaseOpacity:
            state.increaseOpacity()
        case .cycleBrightness:
            state.cycleBrightness()
        case .cycleContrast:
            state.cycleContrast()
        case .cycleGamma:
            state.cycleGamma()
        case .cycleEdgeStrength:
            state.cycleEdgeStrength()
        }
        finishStateChange(hudMessage: hudMessage(for: command))
    }

    private func applyStateToUI() {
        metalView?.preferredFramesPerSecond = state.frameRate
        if state.overlayVisible {
            window?.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
        }
        refreshStatusMenu()
    }

    private func finishStateChange(hudMessage: String?) {
        applyStateToUI()
        if let hudMessage, state.overlayVisible {
            window?.showHUD(hudMessage)
        }
    }

    private func refreshSelectionMenus() {
        for item in gridSelectionMenu?.items ?? [] {
            item.state = item.tag == state.gridIndex ? .on : .off
        }
        for item in styleSelectionMenu?.items ?? [] {
            item.state = item.tag == state.styleIndex ? .on : .off
        }
        for item in renderModeSelectionMenu?.items ?? [] {
            item.state = item.tag == Int(state.renderMode.mode) ? .on : .off
        }
        for item in luminanceSelectionMenu?.items ?? [] {
            item.state = item.tag == state.luminanceMode.bucketCount ? .on : .off
        }

        frameRateSelectionMenu?.removeAllItems()
        for fps in state.supportedFrameRates {
            let item = NSMenuItem(title: "\(fps) FPS", action: #selector(selectFrameRateFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = fps
            item.state = fps == state.frameRate ? .on : .off
            frameRateSelectionMenu?.addItem(item)
        }

        refreshFloatSelectionMenu(opacitySelectionMenu, currentValue: state.overlayOpacity)
        refreshFloatSelectionMenu(brightnessSelectionMenu, currentValue: state.brightness)
        refreshFloatSelectionMenu(contrastSelectionMenu, currentValue: state.contrast)
        refreshFloatSelectionMenu(gammaSelectionMenu, currentValue: state.gamma)
        refreshFloatSelectionMenu(edgeSelectionMenu, currentValue: state.edgeStrength)
    }

    private func hudMessage(for command: HotkeyManager.Command) -> String {
        switch command {
        case .toggleOverlay:
            return state.overlayVisible ? "Overlay: shown" : "Overlay: hidden"
        case .cycleGrid:
            return "Grid: \(state.activeGrid.name) (\(gridCellSizeLabel(for: state.activeGrid.cellSize)))"
        case .cycleStyle:
            return "Style: \(state.activeStyle.name)"
        case .cycleRenderMode:
            return "Render: \(state.renderMode.name)"
        case .toggleLuminance:
            return "Luminance: \(state.luminanceMode.bucketCount) buckets"
        case .cycleFrameRate:
            return "FPS: \(state.frameRate)"
        case .decreaseOpacity, .increaseOpacity:
            return "Opacity: \(Int(state.overlayOpacity * 100))%"
        case .cycleBrightness:
            return String(format: "Brightness: %.2f", state.brightness)
        case .cycleContrast:
            return String(format: "Contrast: %.2f", state.contrast)
        case .cycleGamma:
            return String(format: "Gamma: %.2f", state.gamma)
        case .cycleEdgeStrength:
            return String(format: "Edge: %.2f", state.edgeStrength)
        }
    }

    private func logAppRenderState(reason: String) {
        let renderState = state.sanitizedRenderState()
        print(
            "MacAscii: app-state reason=\(reason) " +
            "visible=\(state.overlayVisible) " +
            "grid=\(state.activeGrid.name) cell-size=\(renderState.cellSize) " +
            "style=\(state.activeStyle.name) style-mode=\(renderState.styleMode) " +
            "render-mode=\(state.renderMode.name) " +
            "luminance-buckets=\(renderState.luminanceBuckets) " +
            "fps=\(state.frameRate) " +
            "opacity=\(Int(renderState.opacity * 100))% " +
            "brightness=\(String(format: "%.2f", renderState.brightness)) " +
            "contrast=\(String(format: "%.2f", renderState.contrast)) " +
            "gamma=\(String(format: "%.2f", renderState.gamma)) " +
            "edge=\(String(format: "%.2f", renderState.edgeStrength)) " +
            "window-level=\(window?.levelDescription ?? "unavailable")"
        )
    }

    private func makeFloatSelectionItem(title: String, value: Float, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = NSNumber(value: value)
        return item
    }

    private func floatValue(from item: NSMenuItem) -> Float? {
        (item.representedObject as? NSNumber)?.floatValue
    }

    private func refreshFloatSelectionMenu(_ menu: NSMenu?, currentValue: Float) {
        for item in menu?.items ?? [] {
            let value = (item.representedObject as? NSNumber)?.floatValue ?? .greatestFiniteMagnitude
            item.state = abs(value - currentValue) < 0.001 ? .on : .off
        }
    }

    private func gridCellSizeLabel(for cellSize: Float) -> String {
        if abs(cellSize.rounded() - cellSize) < 0.001 {
            return String(Int(cellSize.rounded()))
        }
        return String(format: "%.1f", cellSize)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        window?.lowerForMenuAccess()
    }

    func menuDidClose(_ menu: NSMenu) {
        window?.restoreFullscreenOverlayLevel()
        applyStateToUI()
    }
}
