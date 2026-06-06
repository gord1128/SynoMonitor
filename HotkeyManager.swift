import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()
    var action: (() -> Void)?
    
    private init() {}
    
    func register(keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        // 앱 구분을 위한 고유 시그니처 (SYNO)
        hotKeyID.signature = OSType("SYNO".utf8.reduce(0) { $0 << 8 | OSType($1) })
        hotKeyID.id = 1
        
        let eventHandler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            HotkeyManager.shared.action?()
            return noErr
        }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), eventHandler, 1, &eventType, nil, nil)
        
        // 권한 우회를 위해 접근성 API 대신 Carbon 프레임워크의 RegisterEventHotKey 활용
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
