import AppKit
import MetalKit

final class OverlayWindow: NSPanel {
    private static let fullscreenOverlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    private static let menuAccessibleLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)

    init(screen: NSScreen, metalView: MTKView) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        restoreFullscreenOverlayLevel()
        contentView = metalView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func restoreFullscreenOverlayLevel() {
        level = Self.fullscreenOverlayLevel
    }

    func lowerForMenuAccess() {
        level = Self.menuAccessibleLevel
    }

    var levelDescription: String {
        "raw=\(level.rawValue)"
    }
}
