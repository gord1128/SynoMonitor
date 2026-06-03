import Foundation
import Network

class NetworkRouter: ObservableObject {
    static let shared = NetworkRouter()
    
    @Published var activeIP: String = ""
    @Published var isTailscale: Bool = true
    
    private var monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkRouterMonitor")
    
    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.evaluateRoute()
        }
        monitor.start(queue: queue)
        evaluateRoute() // Initial evaluation
    }
    
    func evaluateRoute() {
        let localIP = UserDefaults.standard.string(forKey: "localNasIP") ?? ""
        let tsIP = UserDefaults.standard.string(forKey: "nasIP") ?? ""
        let port = UserDefaults.standard.string(forKey: "nasPort") ?? "5000"
        
        if !localIP.isEmpty {
            // Ping Local IP
            guard let url = URL(string: "http://\(localIP):\(port)/") else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.0
            
            URLSession.shared.dataTask(with: request) { _, response, error in
                let success = error == nil && (response as? HTTPURLResponse)?.statusCode ?? 500 < 500
                DispatchQueue.main.async {
                    if success {
                        self.activeIP = localIP
                        self.isTailscale = false
                    } else {
                        self.activeIP = tsIP
                        self.isTailscale = true
                    }
                }
            }.resume()
        } else {
            DispatchQueue.main.async {
                self.activeIP = tsIP
                self.isTailscale = true
            }
        }
    }
}
