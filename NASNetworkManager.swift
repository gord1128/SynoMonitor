import Foundation
import Combine
import OSLog

@MainActor
class NASNetworkManager: ObservableObject {
    @Published var networkUp: Double = 0.0
    @Published var networkDown: Double = 0.0
    @Published var macNetworkUp: Double = 0.0
    @Published var macNetworkDown: Double = 0.0
    @Published var storagePercentage: Double = 0.0
    @Published var storageFreeTB: Double = 0.0
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
    private var lastFolderSizeFetchDate: Date? = nil
    
    private var lastStorageFetchDate: Date? = nil
    private var activeIP: String { NetworkRouter.shared.activeIP }
    private var nasPort: String { UserDefaults.standard.string(forKey: "nasPort") ?? "5000" }
    private var username: String { UserDefaults.standard.string(forKey: "username") ?? "" }
    private var password: String { KeychainHelper.standard.readString(service: "SynoMonitor", account: "NASPassword") ?? "" }
    
    private var sid: String? = nil
    private var pollingTask: Task<Void, Never>?
    private var isBusy = false
    private var pollingInterval: TimeInterval = 3.0
    
    let logger = Logger(subsystem: "com.SynoMonitor", category: "Network")
    
    func changePollingInterval(_ interval: TimeInterval) {
        guard pollingInterval != interval else { return }
        pollingInterval = interval
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
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if !self.isBusy {
                    self.isBusy = true
                    self.isTailscaleConnected = NetworkRouter.shared.isTailscale
                    
                    await self.fetchData()
                    self.updateMacNetwork()
                    self.isBusy = false
                }
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }
    
    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }
    
    private func updateMacNetwork() {
        let (rx, tx) = LocalNetworkMonitor.shared.getNetworkSpeedInMBps()
        self.macNetworkDown = rx
        self.macNetworkUp = tx
        appendHistory(device: "Mac", rx: rx, tx: tx)
    }
    
    private func appendHistory(device: String, rx: Double, tx: Double) {
        let now = Date()
        historyData.append(SpeedDataPoint(time: now, device: device, type: "다운로드", speed: rx))
        historyData.append(SpeedDataPoint(time: now, device: device, type: "업로드", speed: tx))
        if historyData.count > 120 {
            historyData = Array(historyData.suffix(120))
        }
    }
    
    private func buildURL(api: String, version: String, method: String, extraParams: [String: String] = [:]) -> URL? {
        let ip = activeIP.isEmpty ? (UserDefaults.standard.string(forKey: "nasIP") ?? "") : activeIP
        guard !ip.isEmpty else { return nil }
        let scheme = nasPort == "5001" ? "https" : "http"
        
        let path = api == "SYNO.API.Auth" ? "/webapi/auth.cgi" : "/webapi/entry.cgi"
        var components = URLComponents(string: "\(scheme)://\(ip):\(nasPort)\(path)")
        
        var queryItems = [
            URLQueryItem(name: "api", value: api),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "method", value: method)
        ]
        
        for (key, value) in extraParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        if let sid = sid, api != "SYNO.API.Auth" {
            queryItems.append(URLQueryItem(name: "_sid", value: sid))
        }
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    private func makeRequest(url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return json
    }
    
    private func fetchData() async {
        if sid == nil {
            let success = await authenticate()
            if success {
                await fetchUtilization()
                await attemptFetchStorage()
            }
        } else {
            await fetchUtilization()
            await attemptFetchStorage()
        }
    }
    
    private func attemptFetchStorage() async {
        await fetchStorage()
        
        // Trigger daily folder size scan
        if let lastFetch = lastFolderSizeFetchDate {
            if Date().timeIntervalSince(lastFetch) > 86400 {
                triggerFolderSizeScan()
            }
        } else {
            triggerFolderSizeScan()
        }
    }
    
    private func authenticate() async -> Bool {
        guard !username.isEmpty else { return false }
        guard let url = buildURL(api: "SYNO.API.Auth", version: "3", method: "login", extraParams: [
            "account": username,
            "passwd": password,
            "session": "Core",
            "format": "cookie"
        ]) else { return false }
        
        do {
            let json = try await makeRequest(url: url)
            if let success = json["success"] as? Bool, !success {
                self.errorMessage = "인증 실패 (설정 확인)"
                return false
            }
            if let dataObj = json["data"] as? [String: Any], let sid = dataObj["sid"] as? String {
                self.sid = sid
                self.errorMessage = nil
                
                // Load system info once authenticated
                await fetchSystemInfo()
                return true
            }
        } catch {
            self.errorMessage = "서버 접속 불가"
            self.log("Auth Error: \(error.localizedDescription)")
        }
        return false
    }
    
    private func fetchSystemInfo() async {
        guard let url = buildURL(api: "SYNO.Core.System", version: "1", method: "info") else { return }
        do {
            let json = try await makeRequest(url: url)
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
                if ramMB > 0 {
                    self.totalRamGB = Double(ramMB) / 1024.0
                }
            } else {
                self.nasModel = "No Data"
            }
        } catch {
            self.nasModel = "JSON Err"
        }
    }
    
    private func fetchUtilization() async {
        guard let url = buildURL(api: "SYNO.Core.System.Utilization", version: "1", method: "get") else { return }
        do {
            let json = try await makeRequest(url: url)
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
        } catch { }
    }
    
    private func fetchStorage() async {
        guard let url = buildURL(api: "SYNO.Storage.CGI.Storage", version: "1", method: "load_info") else { return }
        do {
            let json = try await makeRequest(url: url)
            if let success = json["success"] as? Bool, !success {
                self.sid = nil
                self.errorMessage = "세션 만료됨"
                return
            }
            if let dataObj = json["data"] as? [String: Any] {
                if let disks = dataObj["disks"] as? [[String: Any]] {
                    let models = disks.compactMap { $0["model"] as? String }.map { $0.trimmingCharacters(in: .whitespaces) }
                    let uniqueModels = Array(Set(models)).sorted()
                    if !uniqueModels.isEmpty {
                        self.diskModels = uniqueModels.joined(separator: ", ")
                    }
                }
                if let volumes = dataObj["volumes"] as? [[String: Any]] {
                    var totalAll: Double = 0
                    var usedAll: Double = 0
                    
                    for vol in volumes {
                        if let sizeObj = vol["size"] as? [String: Any],
                           let totalStr = sizeObj["total"] as? String,
                           let usedStr = sizeObj["used"] as? String,
                           let t = Double(totalStr), let u = Double(usedStr) {
                            totalAll += t
                            usedAll += u
                        }
                    }
                    
                    if totalAll > 0 {
                        let free = totalAll - usedAll
                        self.storagePercentage = usedAll / totalAll
                        self.storageFreeTB = free / 1_099_511_627_776.0
                        NotificationManager.shared.checkStorage(percentage: self.storagePercentage)
                    }
                }
            }
        } catch { }
        self.lastStorageFetchDate = Date()
    }
    
    // MARK: - Folder Sizes
    
    func triggerFolderSizeScan() {
        guard !self.isFetchingFolderSizes else { return }
        self.isFetchingFolderSizes = true
        
        Task {
            await fetchFolderSizesAsync()
        }
    }
    
    private func fetchFolderSizesAsync() async {
        defer { self.isFetchingFolderSizes = false }
        
        guard let url = buildURL(api: "SYNO.FileStation.List", version: "2", method: "list_share", extraParams: ["additional": "real_path"]) else { return }
        
        do {
            let json = try await makeRequest(url: url)
            guard let dataObj = json["data"] as? [String: Any],
                  let shares = dataObj["shares"] as? [[String: Any]] else {
                return
            }
            
            var currentSizes: [String: Double] = [:]
            for share in shares {
                guard let name = share["name"] as? String, let path = share["path"] as? String else { continue }
                
                let pathArr = [path]
                guard let pathData = try? JSONSerialization.data(withJSONObject: pathArr),
                      let pathStr = String(data: pathData, encoding: .utf8) else {
                    currentSizes[name] = self.folderSizes[name] ?? 0.0
                    continue
                }
                
                if let sizeUrl = buildURL(api: "SYNO.FileStation.DirSize", version: "2", method: "start", extraParams: ["path": pathStr]) {
                    if let sizeJson = try? await makeRequest(url: sizeUrl),
                       let sizeDataObj = sizeJson["data"] as? [String: Any],
                       let taskid = sizeDataObj["taskid"] as? String {
                        
                        let size = await pollFolderSize(taskid: taskid)
                        currentSizes[name] = size ?? (self.folderSizes[name] ?? 0.0)
                    } else {
                        currentSizes[name] = self.folderSizes[name] ?? 0.0
                    }
                }
            }
            
            self.folderSizes = currentSizes
            if let data = try? JSONEncoder().encode(currentSizes) {
                UserDefaults.standard.set(data, forKey: "folderSizes")
            }
            self.lastFolderSizeFetchDate = Date()
            UserDefaults.standard.set(Date(), forKey: "lastFolderSizeFetchDate")
            
        } catch {
            self.log("Folder Scan Error: \(error.localizedDescription)")
        }
    }
    
    private func pollFolderSize(taskid: String) async -> Double? {
        for _ in 0..<30 { // 최대 30번 (약 15초)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
            
            guard let url = buildURL(api: "SYNO.FileStation.DirSize", version: "2", method: "status", extraParams: ["taskid": taskid]) else { break }
            
            do {
                let json = try await makeRequest(url: url)
                guard let dataObj = json["data"] as? [String: Any] else { continue }
                if let finished = dataObj["finished"] as? Bool, finished {
                    let size = dataObj["total_size"] as? Double ?? 0.0
                    // stop 호출 (await 사용 안하고 백그라운드로 쏴버리기)
                    if let stopUrl = buildURL(api: "SYNO.FileStation.DirSize", version: "2", method: "stop", extraParams: ["taskid": taskid]) {
                        _ = try? await makeRequest(url: stopUrl)
                    }
                    return size
                }
            } catch {
                continue
            }
        }
        
        // Timeout 시 stop 호출
        if let stopUrl = buildURL(api: "SYNO.FileStation.DirSize", version: "2", method: "stop", extraParams: ["taskid": taskid]) {
            _ = try? await makeRequest(url: stopUrl)
        }
        return nil
    }
}
