import Foundation

struct SpeedDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let device: String // "NAS", "Mac"
    let type: String // "업로드", "다운로드"
    let speed: Double
}

class LocalNetworkMonitor {
    static let shared = LocalNetworkMonitor()
    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var lastTime: Date?
    
    private init() {}
    
    func getNetworkSpeedInMBps() -> (rx: Double, tx: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        
        var currentRx: UInt64 = 0
        var currentTx: UInt64 = 0
        var ptr = ifaddr
        
        while let interface = ptr?.pointee {
            let name = String(cString: interface.ifa_name)
            // AF_LINK is 18 on macOS
            if interface.ifa_addr != nil && interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                // Ignore loopback
                if !name.hasPrefix("lo") {
                    let data = unsafeBitCast(interface.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                    currentRx += UInt64(data.pointee.ifi_ibytes)
                    currentTx += UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = interface.ifa_next
        }
        
        let now = Date()
        guard let prevTime = lastTime else {
            lastRx = currentRx
            lastTx = currentTx
            lastTime = now
            return (0, 0)
        }
        
        let timeDiff = now.timeIntervalSince(prevTime)
        let diffRx = currentRx >= lastRx ? currentRx - lastRx : 0
        let diffTx = currentTx >= lastTx ? currentTx - lastTx : 0
        
        lastRx = currentRx
        lastTx = currentTx
        lastTime = now
        
        // Convert Bytes/sec to MB/s
        let rxMBps = (timeDiff > 0) ? (Double(diffRx) / timeDiff) / 1_048_576.0 : 0
        let txMBps = (timeDiff > 0) ? (Double(diffTx) / timeDiff) / 1_048_576.0 : 0
        
        return (rxMBps, txMBps)
    }
}
