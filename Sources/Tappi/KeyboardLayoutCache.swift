import Carbon
import Foundation

/// TIS and UCKeyTranslate are confined to startup/layout notifications, never
/// session creation or the event-tap callback. Both cache writes and tap reads
/// run on the main run loop.
final class KeyboardLayoutCache: NSObject {
    private(set) var keyMap = SwitcherKeyMap(currentCharacters: [:])

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(layoutChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
        rebuild()
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func layoutChanged() {
        // Distributed notifications are delivered on the main thread.
        rebuild()
    }

    private func rebuild() {
        let current = Self.characters(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue())
        let ascii = Self.characters(TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue())
        keyMap = SwitcherKeyMap(currentCharacters: current, asciiCharacters: ascii.isEmpty ? nil : ascii)
    }

    private static func characters(_ source: TISInputSource?) -> [Int64: String] {
        guard let source,
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return [:] }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())
        var result: [Int64: String] = [:]
        for code in 0..<128 {
            var deadKeyState: UInt32 = 0
            var length: UniCharCount = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDown), 0, keyboardType,
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                8, &length, &characters)
            if status == noErr, length > 0 {
                result[Int64(code)] = String(utf16CodeUnits: characters, count: Int(length))
            }
        }
        return result
    }
}
