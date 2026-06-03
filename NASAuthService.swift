import Foundation

class NASAuthService {
    enum AuthResult {
        case success(sid: String)
        case requiresOTP
        case failure(errorMsg: String)
    }
    
    func authenticate(username: String, password: String, otpCode: String?, activeIP: String, nasPort: String) async -> AuthResult {
        guard !username.isEmpty else { return .failure(errorMsg: "아이디가 비어있습니다.") }
        guard !activeIP.isEmpty else { return .failure(errorMsg: "IP 주소가 없습니다.") }
        
        let safeUser = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let safePass = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var bodyString = "api=SYNO.API.Auth&version=3&method=login&account=\(safeUser)&passwd=\(safePass)&session=Core&format=cookie"
        
        if let otp = otpCode, !otp.isEmpty {
            let safeOtp = otp.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            bodyString += "&otp_code=\(safeOtp)"
        }
        
        let scheme = nasPort == "5001" ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(activeIP):\(nasPort)/webapi/auth.cgi") else {
            return .failure(errorMsg: "잘못된 URL 설정")
        }
        
        let bodyData = bodyString.data(using: .utf8)
        
        do {
            let json = try await NASAPICore.shared.makeRequest(url: url, method: "POST", body: bodyData)
            
            if let dataObj = json["data"] as? [String: Any], let hasStep2 = dataObj["has_step2"] as? Bool, hasStep2 {
                return .requiresOTP
            }
            
            if let success = json["success"] as? Bool, !success {
                let code = (json["error"] as? [String: Any])?["code"] as? Int ?? 0
                if code == 400 || code == 403 {
                    return .requiresOTP
                }
                return .failure(errorMsg: "인증 실패 (에러코드: \(code))")
            }
            
            if let dataObj = json["data"] as? [String: Any], let sid = dataObj["sid"] as? String {
                return .success(sid: sid)
            }
            
        } catch {
            return .failure(errorMsg: "서버 접속 불가 (\(error.localizedDescription))")
        }
        return .failure(errorMsg: "인증 실패 (알 수 없음)")
    }
}
