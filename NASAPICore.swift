import Foundation

class SSLDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

class NASAPICore {
    static let shared = NASAPICore()
    private init() {}
    
    func buildURL(activeIP: String, nasPort: String, api: String, version: String, method: String, sid: String?, extraParams: [String: String] = [:]) -> URL? {
        let ip = activeIP.isEmpty ? (UserDefaults.standard.string(forKey: "nasIP") ?? "") : activeIP
        guard !ip.isEmpty else { return nil }
        let useHTTPS = UserDefaults.standard.bool(forKey: "useHTTPS")
        let scheme = useHTTPS ? "https" : "http"
        
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
    
    private lazy var isolatedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:] // 프록시 무시
        return URLSession(configuration: config, delegate: SSLDelegate(), delegateQueue: nil)
    }()
    
    func makeRequest(url: URL, method: String = "GET", body: Data? = nil, maxRetries: Int = 3) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = body {
            request.httpBody = body
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 10.0
        
        var currentAttempt = 0
        var lastError: Error?
        
        while currentAttempt <= maxRetries {
            do {
                let (data, _) = try await isolatedSession.data(for: request)
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    print("NASAPICore: JSON Serialization failed")
                    throw URLError(.badServerResponse)
                }
                return json
            } catch {
                print("NASAPICore Request Failed (Attempt \(currentAttempt)): \(error.localizedDescription) for URL: \(url.absoluteString)")
                lastError = error
                currentAttempt += 1
                if currentAttempt <= maxRetries {
                    let delay = Double(1 << (currentAttempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? URLError(.unknown)
    }
}
