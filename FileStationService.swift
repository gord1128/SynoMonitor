import Foundation

class FileStationService {
    func fetchFolderList(activeIP: String, nasPort: String, sid: String) async -> [[String: Any]]? {
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.FileStation.List", version: "2", method: "list_share", sid: sid, extraParams: ["additional": "real_path"]) else { return nil }
        let json = try? await NASAPICore.shared.makeRequest(url: url)
        return (json?["data"] as? [String: Any])?["shares"] as? [[String: Any]]
    }
    
    func startDirSize(activeIP: String, nasPort: String, sid: String, path: String) async -> String? {
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.FileStation.DirSize", version: "2", method: "start", sid: sid, extraParams: ["path": path]) else { return nil }
        let json = try? await NASAPICore.shared.makeRequest(url: url)
        return (json?["data"] as? [String: Any])?["taskid"] as? String
    }
    
    func checkDirSizeStatus(activeIP: String, nasPort: String, sid: String, taskid: String) async -> [String: Any]? {
        let quotedTaskid = "\"\(taskid)\""
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.FileStation.DirSize", version: "2", method: "status", sid: sid, extraParams: ["taskid": quotedTaskid]) else { return nil }
        return try? await NASAPICore.shared.makeRequest(url: url)
    }
    
    func stopDirSize(activeIP: String, nasPort: String, sid: String, taskid: String) async {
        let quotedTaskid = "\"\(taskid)\""
        guard let url = NASAPICore.shared.buildURL(activeIP: activeIP, nasPort: nasPort, api: "SYNO.FileStation.DirSize", version: "2", method: "stop", sid: sid, extraParams: ["taskid": quotedTaskid]) else { return }
        _ = try? await NASAPICore.shared.makeRequest(url: url)
    }
}
