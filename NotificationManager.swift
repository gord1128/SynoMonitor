import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private var lastCpuAlertTime: Date? = nil
    private var lastStorageAlertTime: Date? = nil
    
    private init() {
        requestAuthorization()
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            }
        }
    }
    
    func checkCpu(usage: Double) {
        guard usage >= 0.95 else { return }
        let now = Date()
        if let last = lastCpuAlertTime, now.timeIntervalSince(last) < 3600 { return } // 1시간 쿨타임
        
        sendAlert(title: "⚠️ NAS CPU 경고", body: "CPU 사용률이 \(Int(usage * 100))%에 도달했습니다. 시스템 부하를 확인하세요.")
        lastCpuAlertTime = now
    }
    
    func checkStorage(percentage: Double) {
        guard percentage >= 0.95 else { return }
        let now = Date()
        if let last = lastStorageAlertTime, now.timeIntervalSince(last) < 3600 { return } // 1시간 쿨타임
        
        sendAlert(title: "⚠️ NAS 스토리지 경고", body: "스토리지 사용량이 \(Int(percentage * 100))%를 초과했습니다. 여유 공간을 확보하세요.")
        lastStorageAlertTime = now
    }
    
    private func sendAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
