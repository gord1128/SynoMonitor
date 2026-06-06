import Foundation

class SystemMonitorService {
    func fetchSystemInfo(activeIP: String, nasPort: String, sid: String) async -> [String: Any]? {
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.Core.System", version: "1", method: "info", sid: sid) else { return nil }
        return try? await NASAPICore.shared.makeRequest(url: url)
    }
    
    func fetchUtilization(activeIP: String, nasPort: String, sid: String) async -> [String: Any]? {
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.Core.System.Utilization", version: "1", method: "get", sid: sid) else { return nil }
        return try? await NASAPICore.shared.makeRequest(url: url)
    }
    
    func fetchStorage(activeIP: String, nasPort: String, sid: String) async -> [String: Any]? {
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.Storage.CGI.Storage", version: "1", method: "load_info", sid: sid) else { return nil }
        return try? await NASAPICore.shared.makeRequest(url: url)
    }
    
    func fetchProcessList(activeIP: String, nasPort: String, sid: String) async -> [[String: Any]]? {
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.Core.System.Process", version: "1", method: "list", sid: sid, extraParams: ["sort_by": "cpu", "sort_dir": "DESC", "limit": "5"]) else { return nil }
        let json = try? await NASAPICore.shared.makeRequest(url: url)
        return (json?["data"] as? [String: Any])?["process"] as? [[String: Any]]
    }
}
