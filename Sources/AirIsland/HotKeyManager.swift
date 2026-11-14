import Carbon
import Foundation

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x41495249 // "AIRI"

    private(set) var isRegistered: Bool = false
    var onTrigger: (() -> Void)?

    init() {
        registerOptionSpace()
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func registerOptionSpace() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let eventRef = eventRef, let userData = userData else {
                return OSStatus(eventNotHandledErr)
            }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == 0x41495249, hotKeyID.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onTrigger?()
            }
            return noErr
        }

        let userPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userPtr,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            isRegistered = false
            return
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = (regStatus == noErr && hotKeyRef != nil)
        if !isRegistered, let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
