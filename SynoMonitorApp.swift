import SwiftUI
import Carbon
import Combine

@main
struct SynoMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var popover: NSPopover!
    var statusBarItem: NSStatusItem!
    var settingsWindow: NSWindow?
    let nasManager = NASNetworkManager()
    var cancellables = Set<AnyCancellable>()
    
    @objc func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.center()
            window.isReleasedWhenClosed = false
            window.title = "NAS 접속 설정"
            window.contentView = NSHostingView(rootView: SettingsView(resetAction: {
                self.nasManager.resetData()
            }))
            self.settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI 뷰 셋팅
        let contentView = MonitorView(nasManager: nasManager, openSettings: openSettingsWindow)
        
        // 팝업 오버레이 셋팅
        let popover = NSPopover()
        popover.behavior = .transient // 다른 곳을 클릭하면 자동으로 닫힘
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
        self.popover.delegate = self
        
        // 상단 메뉴바 아이콘 셋팅
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        if let button = self.statusBarItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "SynoMonitor")
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.action = #selector(togglePopover(_:))
        }
        
        // 메뉴바 실시간 속도 업데이트 (UX-01 & SET-01 & UX-02)
        nasManager.$historyData.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                var iconName = "network"
                if self.nasManager.errorMessage != nil {
                    iconName = "exclamationmark.triangle"
                } else if !self.nasManager.isTailscaleConnected {
                    iconName = "network.slash"
                }
                let a11yDesc = iconName == "network" ? "정상 연결됨" : (iconName == "network.slash" ? "오프라인" : "연결 오류")
                self.statusBarItem.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SynoMonitor 상태: \(a11yDesc)")
                
                let pref = UserDefaults.standard.string(forKey: "menubarDisplay") ?? "NAS 다운로드"
                var displayString = ""
                
                switch pref {
                case "NAS 다운로드":
                    displayString = String(format: " %5.1f MB/s", self.nasManager.networkDown)
                case "NAS 업로드":
                    displayString = String(format: " %5.1f MB/s", self.nasManager.networkUp)
                case "Mac 다운로드":
                    displayString = String(format: " %5.1f MB/s", self.nasManager.macNetworkDown)
                case "Mac 업로드":
                    displayString = String(format: " %5.1f MB/s", self.nasManager.macNetworkUp)
                case "컴팩트 (↓/↑)":
                    displayString = String(format: " ↓%4.1f ↑%4.1f", self.nasManager.networkDown, self.nasManager.networkUp)
                default:
                    break
                }
                
                self.statusBarItem.button?.title = displayString
            }
        }.store(in: &cancellables)
        
        // 절전 모드 감지 (NET-02)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(macWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(macDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        
        // 글로벌 단축키 등록 (Option + Cmd + N)
        // Carbon 프레임워크 기준: cmdKey = 256, optionKey = 2048 -> 합산 시 2304.
        // N 키의 키코드는 45
        HotkeyManager.shared.action = { [weak self] in
            DispatchQueue.main.async {
                self?.togglePopover(nil)
            }
        }
        HotkeyManager.shared.register(keyCode: 45, modifiers: UInt32(cmdKey | optionKey))
    }
    
    @objc func macWillSleep() {
        nasManager.stopMonitoring()
    }
    
    @objc func macDidWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.nasManager.startMonitoring()
        }
    }
    
    func popoverDidShow(_ notification: Notification) {
        nasManager.changePollingInterval(1.5)
    }
    
    func popoverDidClose(_ notification: Notification) {
        nasManager.changePollingInterval(300.0) // 5 minutes to protect NAS Hibernation
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let button = statusBarItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
