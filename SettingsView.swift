import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("nasIP") private var nasIP = ""
    @AppStorage("localNasIP") private var localNasIP = ""
    @AppStorage("nasPort") private var nasPort = "5000"
    @AppStorage("username") private var username = ""
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("menubarDisplay") private var menubarDisplay = "NAS 다운로드"
    @AppStorage("customCPUName") private var customCPUName = ""
    @AppStorage("cpuAlertThreshold") private var cpuAlertThreshold: Double = 0.90
    @AppStorage("storageAlertThreshold") private var storageAlertThreshold: Double = 0.90
    @State private var password = ""
    
    var resetAction: (() -> Void)? = nil
    
    let displayOptions = ["NAS 다운로드", "NAS 업로드", "Mac 다운로드", "Mac 업로드", "컴팩트 (↓/↑)", "숨김"]
    
    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Mac 부팅 시 자동 실행", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) {
                            do {
                                if launchAtLogin {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("SMAppService err: \(error)")
                            }
                        }
                    
                    Picker("메뉴바 표시 항목", selection: $menubarDisplay) {
                        ForEach(displayOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                } header: {
                    Text("앱 동작")
                }
                
                Section {
                    HStack {
                        Button("iCloud 설정 백업") {
                            syncToiCloud()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                        
                        Button("iCloud 설정 복원") {
                            syncFromiCloud()
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("iCloud 동기화")
                }
                
                Section {
                    Button(role: .destructive) {
                        resetApp()
                    } label: {
                        Text("초기화 및 로그아웃")
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("일반", systemImage: "gearshape")
            }
            
            Form {
                Section {
                    TextField("Tailscale 접속 IP (예: 100.x.x.x)", text: $nasIP)
                    TextField("로컬 망 접속 IP (예: 192.168.x.x)", text: $localNasIP)
                    TextField("접속 포트", text: $nasPort)
                    if nasPort == "5000" {
                        Text("⚠️ HTTP 연결 중 — HTTPS(5001) 사용을 권장합니다.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("네트워크 설정")
                }
                
                Section {
                    TextField("접속 아이디", text: $username)
                    SecureField("비밀번호 (키체인 암호화)", text: $password)
                        .onChange(of: password) {
                            KeychainHelper.standard.saveString(password, service: "SynoMonitor", account: "NASPassword")
                        }
                } header: {
                    Text("인증 정보")
                } footer: {
                    Text("입력하신 비밀번호는 Apple의 안전한 키체인(Keychain)에 암호화되어 보관됩니다.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("계정", systemImage: "person.crop.circle")
            }
            
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("CPU 알림 임계치: \(Int(cpuAlertThreshold * 100))%")
                        Slider(value: $cpuAlertThreshold, in: 0.5...1.0, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        Text("스토리지 알림 임계치: \(Int(storageAlertThreshold * 100))%")
                        Slider(value: $storageAlertThreshold, in: 0.5...1.0, step: 0.05)
                    }
                } header: {
                    Text("시스템 경고 알림 (알림 쿨타임 1시간)")
                } footer: {
                    Text("NAS의 리소스 사용량이 위 수치를 초과하면 데스크톱 알림이 전송됩니다.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("알림", systemImage: "bell")
            }
            
            Form {
                Section {
                    TextField("강제 표시할 CPU 모델명", text: $customCPUName)
                } header: {
                    Text("헤놀로지 사용자 커스텀 설정")
                } footer: {
                    Text("비워두면 시스템 정보를 자동으로 추출합니다.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("고급", systemImage: "slider.horizontal.3")
            }
        }
        .frame(width: 500, height: 450)
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(title: Text("알림"), message: Text(alertMessage), dismissButton: .default(Text("확인")))
        }
        .onAppear {
            self.password = KeychainHelper.standard.readString(service: "SynoMonitor", account: "NASPassword") ?? ""
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    private var iCloudBackupURL: URL? {
        let fileManager = FileManager.default
        let url = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Mobile Documents/com~apple~CloudDocs/SynoMonitor")
        if let url = url {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url.appendingPathComponent("SettingsBackup.json")
        }
        return nil
    }
    
    private func syncToiCloud() {
        let settings: [String: String] = [
            "nasIP": nasIP,
            "localNasIP": localNasIP,
            "nasPort": nasPort,
            "username": username,
            "menubarDisplay": menubarDisplay,
            "customCPUName": customCPUName
        ]
        
        guard let data = try? JSONEncoder().encode(settings), let url = iCloudBackupURL else {
            alertMessage = "iCloud Drive 경로를 찾을 수 없습니다."
            showAlert = true
            return
        }
        
        do {
            try data.write(to: url)
            alertMessage = "iCloud Drive에 설정이 안전하게 백업되었습니다!\n(경로: iCloud Drive/SynoMonitor/SettingsBackup.json)"
            showAlert = true
        } catch {
            alertMessage = "백업 실패: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func syncFromiCloud() {
        guard let url = iCloudBackupURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let settings = try JSONDecoder().decode([String: String].self, from: data)
            
            if let v = settings["nasIP"] { nasIP = v }
            if let v = settings["localNasIP"] { localNasIP = v }
            if let v = settings["nasPort"] { nasPort = v }
            if let v = settings["username"] { username = v }
            if let v = settings["menubarDisplay"] { menubarDisplay = v }
            if let v = settings["customCPUName"] { customCPUName = v }
            
            alertMessage = "iCloud 백업 파일에서 설정을 성공적으로 복원했습니다."
            showAlert = true
        } catch {
            alertMessage = "복원 실패: 백업 파일이 없거나 읽을 수 없습니다."
            showAlert = true
        }
    }
    
    private func resetApp() {
        KeychainHelper.standard.delete(service: "SynoMonitor", account: "NASPassword")
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
        }
        
        nasIP = ""
        localNasIP = ""
        nasPort = "5000"
        username = ""
        password = ""
        launchAtLogin = false
        menubarDisplay = "NAS 다운로드"
        customCPUName = ""
        cpuAlertThreshold = 0.90
        storageAlertThreshold = 0.90
        
        resetAction?()
        
        alertMessage = "앱이 완전히 초기화되었습니다.\n새로운 계정 정보를 입력해주세요."
        showAlert = true
    }
}
