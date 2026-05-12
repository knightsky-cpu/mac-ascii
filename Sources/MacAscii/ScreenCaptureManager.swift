import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScreenCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "MacAscii.ScreenCapture")
    private let onFrame: (CVPixelBuffer) -> Void

    init(onFrame: @escaping (CVPixelBuffer) -> Void) {
        self.onFrame = onFrame
    }

    func start() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                print("MacAscii: no capturable display found")
                return
            }

            let currentProcessID = ProcessInfo.processInfo.processIdentifier
            let excludedApplications = content.applications.filter { application in
                application.processID == currentProcessID
            }
            let excludedWindows = content.windows.filter { window in
                window.owningApplication?.processID == currentProcessID
            }
            let filter = if excludedApplications.isEmpty {
                SCContentFilter(display: display, excludingWindows: excludedWindows)
            } else {
                SCContentFilter(
                    display: display,
                    excludingApplications: excludedApplications,
                    exceptingWindows: []
                )
            }
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.capturesAudio = false

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            print(
                "MacAscii: capture started display=\(display.width)x\(display.height) " +
                "excluded-apps=\(excludedApplications.count) excluded-windows=\(excludedWindows.count)"
            )
        } catch {
            print("MacAscii: capture failed \(error)")
            print("MacAscii: grant Screen Recording permission to the launching app, then restart MacAscii.")
        }
    }

    func stop() async {
        guard let stream else {
            return
        }

        do {
            try await stream.stopCapture()
        } catch {
            print("MacAscii: capture stop failed \(error)")
        }
        self.stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        onFrame(pixelBuffer)
    }
}
