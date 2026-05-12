import AppKit
import MetalKit

final class OverlayWindow: NSPanel {
    private static let fullscreenOverlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    private static let menuAccessibleLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
    private let hudLabel = NSTextField(labelWithString: "")
    private var hudHideWorkItem: DispatchWorkItem?

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
        configureHUD(in: metalView)
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

    func showHUD(_ message: String) {
        hudHideWorkItem?.cancel()
        hudLabel.stringValue = message
        hudLabel.isHidden = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            hudLabel.animator().alphaValue = 1.0
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.hudLabel.animator().alphaValue = 0.0
            } completionHandler: {
                DispatchQueue.main.async {
                    self.hudLabel.isHidden = true
                }
            }
        }

        hudHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: workItem)
    }

    var levelDescription: String {
        "raw=\(level.rawValue)"
    }

    private func configureHUD(in view: NSView) {
        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.isHidden = true
        hudLabel.alphaValue = 0.0
        hudLabel.textColor = NSColor(calibratedWhite: 0.96, alpha: 1.0)
        hudLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        hudLabel.alignment = .center
        hudLabel.lineBreakMode = .byTruncatingTail
        hudLabel.maximumNumberOfLines = 1
        hudLabel.drawsBackground = true
        hudLabel.backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 0.72)
        hudLabel.wantsLayer = true
        hudLabel.layer?.cornerRadius = 8
        hudLabel.layer?.borderWidth = 1
        hudLabel.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor

        view.addSubview(hudLabel)
        NSLayoutConstraint.activate([
            hudLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            hudLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hudLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.72),
            hudLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
    }
}
