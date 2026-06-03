import SwiftUI
import Charts

struct MonitorView: View {
    @AppStorage("customCPUName") private var customCPUName = ""
    @ObservedObject var nasManager: NASNetworkManager
    @State private var showStorage: Bool = false
    
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
            
            // 텍스트 기반 속도 현황
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAS 업로드: " + String(format: "%.1f MB/s", nasManager.networkUp))
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.blue)
                    Text("Mac 업로드: " + String(format: "%.1f MB/s", nasManager.macNetworkUp))
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.blue.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("NAS 다운로드: " + String(format: "%.1f MB/s", nasManager.networkDown))
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.orange)
                    Text("Mac 다운로드: " + String(format: "%.1f MB/s", nasManager.macNetworkDown))
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.orange.opacity(0.6))
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
                }
            }
            .chartForegroundStyleScale([
                "NAS": Color.orange,
                "Mac": Color.orange.opacity(0.5)
            ])
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(String(format: "%.1f", speed))
                                .font(.system(size: 10, design: .monospaced))
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
                }
            }
            .chartForegroundStyleScale([
                "NAS": Color.blue,
                "Mac": Color.blue.opacity(0.5)
            ])
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(String(format: "%.1f", speed))
                                .font(.system(size: 10, design: .monospaced))
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
                            .font(.caption2.monospacedDigit().bold())
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(nasManager.cpuUsage > 0.8 ? Color.red : Color.blue)
                    .animation(.easeInOut(duration: 0.5), value: nasManager.cpuUsage)
                    
                    let cpuDisplay = customCPUName.isEmpty ? nasManager.cpuModel : customCPUName
                    if !cpuDisplay.isEmpty {
                        Text(cpuDisplay)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 100)
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
                            .font(.caption2.monospacedDigit().bold())
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(nasManager.ramUsage > 0.8 ? Color.red : Color.purple)
                    .animation(.easeInOut(duration: 0.5), value: nasManager.ramUsage)
                    
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
            
            Divider()
            
            Text("숨기려면 ⌥⌘N 입력")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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
    
    private func formatFolderSize(_ bytes: Double) -> String {
        if bytes >= 1_099_511_627_776.0 {
            return String(format: "%.1f TB", bytes / 1_099_511_627_776.0)
        } else if bytes >= 1_073_741_824.0 {
            return String(format: "%.1f GB", bytes / 1_073_741_824.0)
        } else if bytes >= 1_048_576.0 {
            return String(format: "%.1f MB", bytes / 1_048_576.0)
        } else {
            return "\(Int(bytes)) B"
        }
    }
}
