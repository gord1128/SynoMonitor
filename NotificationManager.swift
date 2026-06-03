import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private var lastCpuAlertTime: Date? {
        get { UserDefaults.standard.object(forKey: "lastCpuAlertTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastCpuAlertTime") }
    }
    private var lastStorageAlertTime: Date? {
        get { UserDefaults.standard.object(forKey: "lastStorageAlertTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastStorageAlertTime") }
    }
    
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
        let threshold = UserDefaults.standard.object(forKey: "cpuAlertThreshold") as? Double ?? 0.90
        guard usage >= threshold else { return }
        let now = Date()
        if let last = lastCpuAlertTime, now.timeIntervalSince(last) < 3600 { return } // 1시간 쿨타임
        
        sendAlert(title: "⚠️ NAS CPU 경고", body: "CPU 사용률이 \(Int(usage * 100))%에 도달했습니다. 시스템 부하를 확인하세요.")
        lastCpuAlertTime = now
    }
    
    func checkStorage(percentage: Double) {
        let threshold = UserDefaults.standard.object(forKey: "storageAlertThreshold") as? Double ?? 0.90
        guard percentage >= threshold else { return }
        let now = Date()
        if let last = lastStorageAlertTime, now.timeIntervalSince(last) < 3600 { return } // 1시간 쿨타임
        
        sendAlert(title: "⚠️ NAS 스토리지 경고", body: "스토리지 사용량이 \(Int(percentage * 100))%를 초과했습니다. 여유 공간을 확보하세요.")
        lastStorageAlertTime = now
    }
    
    func checkStorageVolume(name: String, percentage: Double) {
        let key = "storageAlert_\(name)"
        let threshold = UserDefaults.standard.object(forKey: key) as? Double
            ?? UserDefaults.standard.object(forKey: "storageAlertThreshold") as? Double
            ?? 0.90
        guard percentage >= threshold else { return }
        let now = Date()
        let cooldownKey = "lastStorageVolumeAlert_\(name)"
        if let last = UserDefaults.standard.object(forKey: cooldownKey) as? Date, now.timeIntervalSince(last) < 3600 { return }
        
        sendAlert(title: "⚠️ \(name) 용량 경고", body: "\(name) 사용량이 \(Int(percentage * 100))%를 초과했습니다.")
        UserDefaults.standard.set(now, forKey: cooldownKey)
    }
    
    private func sendAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "SynoMonitor_\(title)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
