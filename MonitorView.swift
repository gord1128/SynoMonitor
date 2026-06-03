import SwiftUI
import Charts

struct MonitorView: View {
    @AppStorage("customCPUName") private var customCPUName = ""
    @ObservedObject var nasManager: NASNetworkManager
    @State private var showStorage: Bool = false
    @State private var otpCode: String = ""
    
    private var specText: String {
        var text = nasManager.nasModel
        if !nasManager.firmwareVer.isEmpty {
            text += (text.isEmpty ? "" : " • ") + nasManager.firmwareVer
        }
        return text
    }
    
    var openSettings: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
            // 헤더 & Tailscale 상태
            HStack {
                Text("SynoMonitor")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .imageScale(.medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
                .padding(.leading, 4)
                Button(action: {
                    let activeIP = NetworkRouter.shared.activeIP
                    let tsIP = UserDefaults.standard.string(forKey: "nasIP") ?? ""
                    let port = UserDefaults.standard.string(forKey: "nasPort") ?? "5000"
                    let scheme = port == "5001" ? "https" : "http"
                    let ip = activeIP.isEmpty ? tsIP : activeIP
                    if !ip.isEmpty, let url = URL(string: "\(scheme)://\(ip):\(port)/") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "safari.fill")
                        .imageScale(.medium)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
                .padding(.leading, 4)
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .imageScale(.medium)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
                .padding(.leading, 4)
                
                Spacer()
                Circle()
                    .fill(nasManager.errorMessage != nil ? Color.red : (nasManager.isTailscaleConnected ? Color.green : Color.blue))
                    .frame(width: 8, height: 8)
                Text(nasManager.errorMessage != nil ? "Error" : (nasManager.isTailscaleConnected ? "TS" : "Local"))
                    .font(.caption2)
                    .foregroundColor(nasManager.errorMessage != nil ? .red : (nasManager.isTailscaleConnected ? .green : .blue))
            }
            
            if nasManager.requiresOTP {
                Divider()
                VStack(alignment: .center, spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("2단계 인증 필요")
                        .font(.headline)
                    Text("NAS 보안 설정에 의해 OTP 코드가 필요합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    TextField("6자리 코드 입력", text: $otpCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                        .multilineTextAlignment(.center)
                    
                    Button("인증하기") {
                        nasManager.submitOTP(otpCode)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                if !specText.isEmpty || !nasManager.diskModels.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if !specText.isEmpty {
                            Text(specText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if !nasManager.diskModels.isEmpty {
                            Text("Disks: \(nasManager.diskModels)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                } else {
                    Spacer().frame(height: 4)
                }
                
                if let errorMsg = nasManager.errorMessage {
                    Text("⚠️ " + errorMsg)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.8).cornerRadius(8))
                }
                
                Divider()
                
                ZStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 12) {
            
            // 텍스트 기반 속도 현황
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.blue)
                        Text("NAS 업로드: " + String(format: "%.1f MB/s", nasManager.networkUp))
                            .font(.system(.footnote, design: .rounded).monospacedDigit())
                            .foregroundColor(.blue)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle")
                            .foregroundColor(.blue.opacity(0.6))
                        Text("Mac 업로드: " + String(format: "%.1f MB/s", nasManager.macNetworkUp))
                            .font(.system(.footnote, design: .rounded).monospacedDigit())
                            .foregroundColor(.blue.opacity(0.6))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("NAS 다운로드: " + String(format: "%.1f MB/s", nasManager.networkDown))
                            .font(.system(.footnote, design: .rounded).monospacedDigit())
                            .foregroundColor(.orange)
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.orange)
                    }
                    HStack(spacing: 4) {
                        Text("Mac 다운로드: " + String(format: "%.1f MB/s", nasManager.macNetworkDown))
                            .font(.system(.footnote, design: .rounded).monospacedDigit())
                            .foregroundColor(.orange.opacity(0.6))
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.orange.opacity(0.6))
                    }
                }
            }
            
            Divider()
            
            // 차트 영역 (다운로드/업로드 분리)
            Text("다운로드 실시간 그래프 (MB/s)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Chart {
                ForEach(nasManager.historyData.filter { $0.type == "다운로드" }) { item in
                    LineMark(
                        x: .value("Time", item.time),
                        y: .value("Speed", item.speed)
                    )
                    .foregroundStyle(by: .value("Device", item.device))
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", item.time),
                        y: .value("Speed", item.speed)
                    )
                    .foregroundStyle(by: .value("Device", item.device))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale([
                "NAS": AnyShapeStyle(LinearGradient(gradient: Gradient(colors: [Color.orange.opacity(0.5), Color.orange.opacity(0.0)]), startPoint: .top, endPoint: .bottom)),
                "Mac": AnyShapeStyle(LinearGradient(gradient: Gradient(colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.0)]), startPoint: .top, endPoint: .bottom))
            ])
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(String(format: "%.1f", speed))
                                .font(.system(size: 10, design: .rounded))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 80)
            
            Text("업로드 실시간 그래프 (MB/s)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Chart {
                ForEach(nasManager.historyData.filter { $0.type == "업로드" }) { item in
                    LineMark(
                        x: .value("Time", item.time),
                        y: .value("Speed", item.speed)
                    )
                    .foregroundStyle(by: .value("Device", item.device))
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", item.time),
                        y: .value("Speed", item.speed)
                    )
                    .foregroundStyle(by: .value("Device", item.device))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale([
                "NAS": AnyShapeStyle(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.5), Color.blue.opacity(0.0)]), startPoint: .top, endPoint: .bottom)),
                "Mac": AnyShapeStyle(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.0)]), startPoint: .top, endPoint: .bottom))
            ])
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(String(format: "%.1f", speed))
                                .font(.system(size: 10, design: .rounded))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 80)
            
            Divider()
            
            // 시스템 리소스 영역
            HStack(spacing: 40) {
                Spacer()
                VStack(spacing: 6) {
                    Gauge(value: nasManager.cpuUsage, in: 0...1) {
                        Text("CPU")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    } currentValueLabel: {
                        Text("\(Int(nasManager.cpuUsage * 100))%")
                            .font(.system(.caption2, design: .rounded).monospacedDigit().bold())
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(nasManager.cpuUsage > 0.8 ? Color.red : Color.blue)
                    .animation(.easeInOut(duration: 0.5), value: nasManager.cpuUsage)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("CPU 사용량")
                    .accessibilityValue("\(Int(nasManager.cpuUsage * 100)) 퍼센트")
                    
                    let cpuDisplay = customCPUName.isEmpty ? nasManager.cpuModel : customCPUName
                    if !cpuDisplay.isEmpty {
                        Text(cpuDisplay)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 140)
                    } else {
                        Text(" ")
                            .font(.system(size: 9))
                    }
                }
                
                VStack(spacing: 6) {
                    Gauge(value: nasManager.ramUsage, in: 0...1) {
                        Text("RAM")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    } currentValueLabel: {
                        Text("\(Int(nasManager.ramUsage * 100))%")
                            .font(.system(.caption2, design: .rounded).monospacedDigit().bold())
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(nasManager.ramUsage > 0.8 ? Color.red : Color.purple)
                    .animation(.easeInOut(duration: 0.5), value: nasManager.ramUsage)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("RAM 사용량")
                    .accessibilityValue("\(Int(nasManager.ramUsage * 100)) 퍼센트")
                    
                    if nasManager.totalRamGB > 0 {
                        Text("\(Int(round(nasManager.totalRamGB))) GB")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else {
                        Text(" ")
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            
            if !nasManager.topProcesses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU 상위 프로세스")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.orange)
                    ForEach(nasManager.topProcesses) { proc in
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 8))
                                .foregroundColor(proc.cpu > 50 ? .red : .secondary)
                            Text(proc.name)
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(String(format: "CPU %.0f%%", proc.cpu))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(proc.cpu > 50 ? .red : .secondary)
                            Text(String(format: "RAM %.0f%%", proc.ram))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
            
            Divider()
            Button(action: {
                withAnimation(.spring()) {
                    showStorage.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "internaldrive")
                    Text("스토리지 및 공유 폴더 상세 정보")
                    Spacer()
                    Image(systemName: showStorage ? "chevron.left" : "chevron.right")
                        .animation(.spring(), value: showStorage)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            }
            .blur(radius: nasManager.errorMessage != nil ? 3 : 0)
            .grayscale(nasManager.errorMessage != nil ? 0.8 : 0)
            .disabled(nasManager.errorMessage != nil)
            
            if nasManager.errorMessage != nil {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text("오프라인 상태")
                        .font(.headline)
                    Text("데이터 갱신 중지됨")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
                .cornerRadius(12)
                .shadow(radius: 5)
            }
            } // Close ZStack
            
            Divider()
            
            Text("숨기려면 ⌥⌘N 입력")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            } // Close `else` block
        } // Close VStack
        .padding()
        .frame(width: 320, alignment: .top)
        
        if showStorage {
            Divider()
            
            StorageView(nasManager: nasManager)
                .frame(width: 340, alignment: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        }
        .fixedSize()
    }
}
