import AppKit
import MetalKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var window: OverlayWindow?
    private var renderer: Renderer?
    private var captureManager: ScreenCaptureManager?
    private var hotkeyManager: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var gridMenuItem: NSMenuItem?
    private var styleMenuItem: NSMenuItem?
    private var luminanceMenuItem: NSMenuItem?

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

        let metalView = MTKView(frame: screen.frame, device: device)
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = 30
        print(
            "MacAscii: screen frame=\(Int(screen.frame.width))x\(Int(screen.frame.height)) " +
            "scale=\(screen.backingScaleFactor)"
        )

        guard let renderer = Renderer(
            metalView: metalView,
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
        print("MacAscii: hotkeys Ctrl+Option+A toggle, Ctrl+Option+. grid, Ctrl+Option+' style, Ctrl+Option+, luminance")
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

        let cycleStyleItem = NSMenuItem(
            title: "Cycle Style",
            action: #selector(cycleStyleFromMenu),
            keyEquivalent: ""
        )
        cycleStyleItem.target = self
        menu.addItem(cycleStyleItem)

        let toggleLuminanceItem = NSMenuItem(
            title: "Toggle 10/20 Luminance",
            action: #selector(toggleLuminanceFromMenu),
            keyEquivalent: ""
        )
        toggleLuminanceItem.target = self
        menu.addItem(toggleLuminanceItem)

        let gridMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        gridMenuItem.isEnabled = false
        menu.addItem(gridMenuItem)

        let styleMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        styleMenuItem.isEnabled = false
        menu.addItem(styleMenuItem)

        let luminanceMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        luminanceMenuItem.isEnabled = false
        menu.addItem(luminanceMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MacAscii", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.toggleMenuItem = toggleMenuItem
        self.gridMenuItem = gridMenuItem
        self.styleMenuItem = styleMenuItem
        self.luminanceMenuItem = luminanceMenuItem
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        toggleMenuItem?.title = state.overlayVisible ? "Hide Overlay" : "Show Overlay"
        gridMenuItem?.title = "Grid: \(state.activeGrid.name) (\(Int(state.activeGrid.cellSize)))"
        styleMenuItem?.title = "Style: \(state.activeStyle.name)"
        luminanceMenuItem?.title = "Luminance: \(state.luminanceMode.bucketCount) buckets"
    }

    @objc private func toggleOverlayFromMenu() {
        handle(command: .toggleOverlay)
    }

    @objc private func cycleGridFromMenu() {
        handle(command: .cycleGrid)
    }

    @objc private func cycleStyleFromMenu() {
        handle(command: .cycleStyle)
    }

    @objc private func toggleLuminanceFromMenu() {
        handle(command: .toggleLuminance)
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
        case .toggleLuminance:
            state.toggleLuminanceMode()
        }
        applyStateToUI()
    }

    private func applyStateToUI() {
        if state.overlayVisible {
            window?.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
        }
        refreshStatusMenu()
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
