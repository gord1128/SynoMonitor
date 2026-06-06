import Foundation
import Combine
import OSLog

struct VolumeInfo: Identifiable {
    let id = UUID()
    let name: String
    let totalBytes: Double
    let usedBytes: Double
    var percentage: Double { totalBytes > 0 ? usedBytes / totalBytes : 0 }
}

struct ProcessInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let cpu: Double
    let ram: Double
}

@MainActor
class NASNetworkManager: ObservableObject {
    @Published var networkUp: Double = 0.0
    @Published var networkDown: Double = 0.0
    @Published var macNetworkUp: Double = 0.0
    @Published var macNetworkDown: Double = 0.0
    @Published var storagePercentage: Double = 0.0
    @Published var storageFreeTB: Double = 0.0
    @Published var storageTotalBytes: Double = 0.0
    @Published var cpuUsage: Double = 0.0
    @Published var ramUsage: Double = 0.0
    @Published var nasModel: String = ""
    @Published var cpuModel: String = ""
    @Published var diskModels: String = ""
    @Published var firmwareVer: String = ""
    @Published var totalRamGB: Double = 0.0
    @Published var isTailscaleConnected: Bool = false
    @Published var historyData: [SpeedDataPoint] = []
    @Published var errorMessage: String? = nil
    
    @Published var folderSizes: [String: Double] = [:]
    @Published var isFetchingFolderSizes: Bool = false
    @Published var requiresOTP: Bool = false
    @Published var topProcesses: [ProcessInfo] = []
    @Published var volumes: [VolumeInfo] = []
    
    private var consecutiveAuthFailures = 0
    private let maxAuthRetries = 5
    private var lastAuthAttempt: Date = Date.distantPast
    
    private var lastFolderSizeFetchDate: Date? = nil
    private var lastStorageFetchDate: Date? = nil
    
    private var activeIP: String { NetworkRouter.shared.activeIP }
    private var nasPort: String { UserDefaults.standard.string(forKey: "nasPort") ?? "5000" }
    private var username: String { UserDefaults.standard.string(forKey: "username") ?? "" }
    private var password: String { KeychainHelper.standard.readString(service: "SynoMonitor", account: "NASPassword") ?? "" }
    
    private var sid: String? = nil
    private var pollingTask: Task<Void, Never>?
    private var macPollingTask: Task<Void, Never>?
    private var folderScanTask: Task<Void, Never>?
    private var isBusy = false
    private var pollingInterval: TimeInterval = 3.0
    
    let logger = Logger(subsystem: "com.SynoMonitor", category: "Network")
    
    private let authService = NASAuthService()
    private let sysService = SystemMonitorService()
    private let fileService = FileStationService()
    
    func changePollingInterval(_ interval: TimeInterval) {
        guard pollingInterval != interval else { return }
        pollingInterval = interval
        if interval == 1.5 {
            self.consecutiveAuthFailures = 0
        }
        startMonitoring()
    }
    
    func log(_ msg: String) {
        logger.error("\(msg)")
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "folderSizes"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.folderSizes = decoded
        }
        self.lastFolderSizeFetchDate = UserDefaults.standard.object(forKey: "lastFolderSizeFetchDate") as? Date
        startMonitoring()
    }
    
    func startMonitoring() {
        pollingTask?.cancel()
        macPollingTask?.cancel()
        
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if !self.isBusy {
                    self.isBusy = true
                    self.isTailscaleConnected = NetworkRouter.shared.isTailscale
                    
                    await self.fetchData()
                    self.isBusy = false
                }
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
        
        macPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.updateMacNetwork()
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // Always 1.0s
                } catch {
                    break
                }
            }
        }
    }
    
    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        macPollingTask?.cancel()
        macPollingTask = nil
    }
    
    private func updateMacNetwork() {
        Task.detached(priority: .background) { [weak self] in
            let (rx, tx) = LocalNetworkMonitor.shared.getNetworkSpeedInMBps()
            await MainActor.run {
                guard let self = self else { return }
                self.macNetworkDown = rx
                self.macNetworkUp = tx
                self.appendHistory(device: "Mac", rx: rx, tx: tx)
            }
        }
    }
    
    private func appendHistory(device: String, rx: Double, tx: Double) {
        let now = Date()
        historyData.append(SpeedDataPoint(time: now, device: device, type: "다운로드", speed: rx))
        historyData.append(SpeedDataPoint(time: now, device: device, type: "업로드", speed: tx))
        if historyData.count > 120 {
            historyData = Array(historyData.suffix(120))
        }
    }
    
    func retryConnection() {
        self.consecutiveAuthFailures = 0
        self.errorMessage = nil
        Task { await self.fetchData() }
    }
    
    func resetData() {
        stopMonitoring()
        self.sid = nil
        self.errorMessage = nil
        self.requiresOTP = false
        self.historyData.removeAll()
        self.folderSizes.removeAll()
        self.cpuUsage = 0
        self.ramUsage = 0
        self.networkUp = 0
        self.networkDown = 0
        self.macNetworkUp = 0
        self.macNetworkDown = 0
        self.storagePercentage = 0
        self.storageFreeTB = 0
        self.storageTotalBytes = 0
        self.cpuModel = ""
        self.nasModel = ""
        self.diskModels = ""
        self.topProcesses = []
        self.volumes = []
        startMonitoring()
    }
    
    func submitOTP(_ otpCode: String) {
        Task {
            _ = await authenticate(otpCode: otpCode)
        }
    }
    
    private func fetchData() async {
        if sid == nil {
            if consecutiveAuthFailures >= maxAuthRetries {
                if Date().timeIntervalSince(lastAuthAttempt) < 60 {
                    self.errorMessage = "서버 연결 실패 (60초 후 자동 재시도)"
                    return
                } else {
                    consecutiveAuthFailures = 0
                    self.errorMessage = "자동 재연결 시도 중..."
                }
            }
            
            lastAuthAttempt = Date()
            let authResult = await authenticate()
            
            switch authResult {
            case .success:
                consecutiveAuthFailures = 0
                await fetchUtilization()
                await attemptFetchStorage()
            case .authError:
                consecutiveAuthFailures += 1
            case .networkError:
                // Do not increment consecutiveAuthFailures for network errors (e.g. Tailscale initializing)
                // We want to keep retrying without 60s penalty
                break
            }
        } else {
            await fetchUtilization()
            await attemptFetchStorage()
        }
    }
    
    enum AuthAttemptResult {
        case success
        case authError
        case networkError
    }
    
    private func authenticate(otpCode: String? = nil) async -> AuthAttemptResult {
        let result = await authService.authenticate(username: username, password: password, otpCode: otpCode, activeIP: activeIP, nasPort: nasPort)
        
        switch result {
        case .success(let sid):
            self.sid = sid
            self.errorMessage = nil
            self.requiresOTP = false
            await fetchSystemInfo()
            return .success
        case .requiresOTP:
            self.errorMessage = "2단계 인증(OTP)이 필요합니다."
            self.requiresOTP = true
            return .authError
        case .failure(let msg):
            self.errorMessage = msg
            if msg.contains("서버 접속 불가") || msg.contains("IP 주소가 없습니다") || msg.contains("잘못된 URL") {
                return .networkError
            } else {
                return .authError
            }
        }
    }
    
    private func attemptFetchStorage() async {
        await fetchStorage()
        
        if let lastFetch = lastFolderSizeFetchDate {
            if Date().timeIntervalSince(lastFetch) > 86400 {
                triggerFolderSizeScan()
            }
        } else {
            triggerFolderSizeScan()
        }
    }
    
    private func fetchSystemInfo() async {
        guard let s = sid else { return }
        if let json = await sysService.fetchSystemInfo(activeIP: activeIP, nasPort: nasPort, sid: s) {
            if let success = json["success"] as? Bool, !success {
                let code = (json["error"] as? [String: Any])?["code"] as? Int ?? 0
                self.nasModel = "API Err: \(code)"
                return
            }
            if let dataObj = json["data"] as? [String: Any] {
                let cpuFamily = dataObj["cpu_family"] as? String ?? ""
                let cpuVendor = dataObj["cpu_vendor"] as? String ?? ""
                let cpuCores = dataObj["cpu_cores"] as? Int ?? 0
                
                var cpuStr = cpuFamily
                if cpuStr.isEmpty { cpuStr = cpuVendor }
                if cpuStr.isEmpty && cpuCores > 0 { cpuStr = "\(cpuCores)-Core CPU" }
                if cpuStr.isEmpty {
                    let cpuKeys = dataObj.keys.filter { $0.contains("cpu") }
                    cpuStr = cpuKeys.isEmpty ? "Unknown" : cpuKeys.joined(separator: ",")
                }
                
                self.cpuModel = cpuStr
                self.nasModel = dataObj["model"] as? String ?? "Unknown Model"
                self.firmwareVer = dataObj["firmware_ver"] as? String ?? ""
                let ramMB = dataObj["ram_size"] as? Int ?? 0
                if ramMB > 0 { self.totalRamGB = Double(ramMB) / 1024.0 }
            } else {
                self.nasModel = "No Data"
            }
        } else {
            self.nasModel = "JSON Err"
        }
    }
    
    private func fetchUtilization() async {
        guard let s = sid else { return }
        if let json = await sysService.fetchUtilization(activeIP: activeIP, nasPort: nasPort, sid: s) {
            if let success = json["success"] as? Bool, !success {
                self.sid = nil
                return
            }
            if let dataObj = json["data"] as? [String: Any] {
                if let network = dataObj["network"] as? [[String: Any]], let firstNet = network.first {
                    let rx = firstNet["rx"] as? Double ?? 0
                    let tx = firstNet["tx"] as? Double ?? 0
                    self.networkDown = rx / 1_048_576.0
                    self.networkUp = tx / 1_048_576.0
                    self.appendHistory(device: "NAS", rx: self.networkDown, tx: self.networkUp)
                }
                if let cpuObj = dataObj["cpu"] as? [String: Any] {
                    let sys = cpuObj["system_load"] as? Int ?? 0
                    let user = cpuObj["user_load"] as? Int ?? 0
                    let other = cpuObj["other_load"] as? Int ?? 0
                    self.cpuUsage = Double(sys + user + other) / 100.0
                    NotificationManager.shared.checkCpu(usage: self.cpuUsage)
                    
                    if self.cpuUsage >= 0.7 {
                        await fetchTopProcesses()
                    } else {
                        self.topProcesses = []
                    }
                }
                if let memObj = dataObj["memory"] as? [String: Any] {
                    let usage = memObj["real_usage"] as? Int ?? 0
                    let totalRealKB = memObj["total_real"] as? Int ?? 0
                    self.ramUsage = Double(usage) / 100.0
                    if self.totalRamGB == 0.0 && totalRealKB > 0 {
                        self.totalRamGB = Double(totalRealKB) / 1_048_576.0
                    }
                }
            }
        }
    }
    
    private func fetchTopProcesses() async {
        guard let s = sid else { return }
        guard let processes = await sysService.fetchProcessList(activeIP: activeIP, nasPort: nasPort, sid: s) else {
            self.topProcesses = []
            return
        }
        self.topProcesses = Array(processes.prefix(3).compactMap { proc -> ProcessInfo? in
            guard let name = proc["name"] as? String else { return nil }
            let cpu = (proc["cpu"] as? Double) ?? Double(proc["cpu"] as? Int ?? 0)
            let ram = (proc["mem"] as? Double) ?? Double(proc["mem"] as? Int ?? 0)
            return ProcessInfo(name: name, cpu: cpu, ram: ram)
        })
    }
    
    private func fetchStorage() async {
        guard let s = sid else { return }
        if let json = await sysService.fetchStorage(activeIP: activeIP, nasPort: nasPort, sid: s) {
            if let success = json["success"] as? Bool, !success {
                self.sid = nil
                self.errorMessage = "세션 만료됨"
                return
            }
            if let dataObj = json["data"] as? [String: Any] {
                if let disks = dataObj["disks"] as? [[String: Any]] {
                    let models = disks.compactMap { $0["model"] as? String }.map { $0.trimmingCharacters(in: .whitespaces) }
                    let uniqueModels = Array(Set(models)).sorted()
                    if !uniqueModels.isEmpty { self.diskModels = uniqueModels.joined(separator: ", ") }
                }
                if let volumesArr = dataObj["volumes"] as? [[String: Any]] {
                    var totalAll: Double = 0
                    var usedAll: Double = 0
                    var parsedVolumes: [VolumeInfo] = []
                    for vol in volumesArr {
                        if let sizeObj = vol["size"] as? [String: Any],
                           let totalStr = sizeObj["total"] as? String, let usedStr = sizeObj["used"] as? String,
                           let t = Double(totalStr), let u = Double(usedStr) {
                            totalAll += t
                            usedAll += u
                            let volName = vol["id"] as? String ?? vol["volume_path"] as? String ?? "volume\(parsedVolumes.count + 1)"
                            parsedVolumes.append(VolumeInfo(name: volName, totalBytes: t, usedBytes: u))
                            NotificationManager.shared.checkStorageVolume(name: volName, percentage: t > 0 ? u / t : 0)
                        }
                    }
                    self.volumes = parsedVolumes
                    if totalAll > 0 {
                        let free = totalAll - usedAll
                        self.storagePercentage = usedAll / totalAll
                        self.storageFreeTB = free / 1_099_511_627_776.0
                        self.storageTotalBytes = totalAll
                        NotificationManager.shared.checkStorage(percentage: self.storagePercentage)
                    }
                }
            }
        }
        self.lastStorageFetchDate = Date()
    }
    
    func triggerFolderSizeScan() {
        if isFetchingFolderSizes { folderScanTask?.cancel() }
        self.isFetchingFolderSizes = true
        folderScanTask = Task {
            await fetchFolderSizesAsync()
            self.folderScanTask = nil
        }
    }
    
    private func fetchFolderSizesAsync() async {
        defer { self.isFetchingFolderSizes = false }
        guard let s = sid else { return }
        
        guard let shares = await fileService.fetchFolderList(activeIP: activeIP, nasPort: nasPort, sid: s) else { return }
        
        var currentSizes: [String: Double] = [:]
        
        // Concurrency Limit logic
        await withTaskGroup(of: (String, Double?).self) { group in
            var activeTasks = 0
            let maxConcurrentTasks = 2 // Limited to 2 for hibernation/IO protection
            
            var shareIterator = shares.makeIterator()
            
            // Initial batch
            while activeTasks < maxConcurrentTasks, let share = shareIterator.next() {
                if let name = share["name"] as? String, let path = share["path"] as? String,
                   let pathData = try? JSONSerialization.data(withJSONObject: [path]),
                   let pathStr = String(data: pathData, encoding: .utf8) {
                    
                    activeTasks += 1
                    group.addTask {
                        let size = await self.fetchSingleFolderSize(pathStr: pathStr, sid: s)
                        return (name, size)
                    }
                }
            }
            
            // Drain and spawn
            for await (name, size) in group {
                activeTasks -= 1
                currentSizes[name] = size ?? (self.folderSizes[name] ?? 0.0)
                
                while activeTasks < maxConcurrentTasks, let share = shareIterator.next() {
                    if let name = share["name"] as? String, let path = share["path"] as? String,
                       let pathData = try? JSONSerialization.data(withJSONObject: [path]),
                       let pathStr = String(data: pathData, encoding: .utf8) {
                        
                        activeTasks += 1
                        group.addTask {
                            let size = await self.fetchSingleFolderSize(pathStr: pathStr, sid: s)
                            return (name, size)
                        }
                    }
                }
            }
        }
        
        self.folderSizes = currentSizes
        if let data = try? JSONEncoder().encode(currentSizes) { UserDefaults.standard.set(data, forKey: "folderSizes") }
        self.lastFolderSizeFetchDate = Date()
        UserDefaults.standard.set(Date(), forKey: "lastFolderSizeFetchDate")
    }
    
    private func fetchSingleFolderSize(pathStr: String, sid: String) async -> Double? {
        if let taskid = await fileService.startDirSize(activeIP: activeIP, nasPort: nasPort, sid: sid, path: pathStr) {
            return await pollFolderSize(taskid: taskid, sid: sid)
        }
        return nil
    }
    
    private func pollFolderSize(taskid: String, sid: String) async -> Double? {
        for _ in 0..<60 {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { break }
            
            if let json = await fileService.checkDirSizeStatus(activeIP: activeIP, nasPort: nasPort, sid: sid, taskid: taskid),
               let dataObj = json["data"] as? [String: Any],
               let finished = dataObj["finished"] as? Bool, finished {
                
                var size = 0.0
                if let s = dataObj["total_size"] as? Double { size = s }
                else if let s = dataObj["total_size"] as? String, let d = Double(s) { size = d }
                else if let s = dataObj["total_size"] as? Int { size = Double(s) }
                else if let s = dataObj["total_size"] as? Int64 { size = Double(s) }
                
                await fileService.stopDirSize(activeIP: activeIP, nasPort: nasPort, sid: sid, taskid: taskid)
                return size
            }
        }
        await fileService.stopDirSize(activeIP: activeIP, nasPort: nasPort, sid: sid, taskid: taskid)
        return -1.0
    }
}
