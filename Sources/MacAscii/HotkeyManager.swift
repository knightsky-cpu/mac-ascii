import Carbon
import Foundation

final class HotkeyManager {
    enum Command: UInt32 {
        case toggleOverlay = 1
        case cycleGrid = 2
        case cycleStyle = 3
        case toggleLuminance = 4
        case decreaseOpacity = 5
        case increaseOpacity = 6
        case cycleBrightness = 7
        case cycleContrast = 8
        case cycleGamma = 9
        case cycleEdgeStrength = 10
    }

    private var hotkeys: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private let handler: (Command) -> Void

    init(handler: @escaping (Command) -> Void) {
        self.handler = handler
    }

    func start() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let command = Command(rawValue: hotkeyID.id) {
                    manager.handler(command)
                }

                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        guard status == noErr else {
            print("MacAscii: failed to install hotkey handler status=\(status)")
            return
        }

        register(command: .toggleOverlay, keyCode: UInt32(kVK_ANSI_A))
        register(command: .cycleGrid, keyCode: UInt32(kVK_ANSI_Period))
        register(command: .cycleStyle, keyCode: UInt32(kVK_ANSI_Quote))
        register(command: .toggleLuminance, keyCode: UInt32(kVK_ANSI_Comma))
        register(command: .decreaseOpacity, keyCode: UInt32(kVK_ANSI_Minus))
        register(command: .increaseOpacity, keyCode: UInt32(kVK_ANSI_Equal))
        register(command: .cycleBrightness, keyCode: UInt32(kVK_ANSI_B))
        register(command: .cycleContrast, keyCode: UInt32(kVK_ANSI_C))
        register(command: .cycleGamma, keyCode: UInt32(kVK_ANSI_G))
        register(command: .cycleEdgeStrength, keyCode: UInt32(kVK_ANSI_E))
    }

    func stop() {
        for hotkey in hotkeys {
            if let hotkey {
                UnregisterEventHotKey(hotkey)
            }
        }
        hotkeys.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register(command: Command, keyCode: UInt32) {
        var hotkey: EventHotKeyRef?
        let signature = OSType(
            UInt32(Character("M").asciiValue!) << 24 |
            UInt32(Character("A").asciiValue!) << 16 |
            UInt32(Character("S").asciiValue!) << 8 |
            UInt32(Character("C").asciiValue!)
        )
        let hotkeyID = EventHotKeyID(signature: signature, id: command.rawValue)
        let modifiers = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkey)

        if status == noErr {
            hotkeys.append(hotkey)
        } else {
            print("MacAscii: failed to register hotkey command=\(command) status=\(status)")
        }
    }
}
