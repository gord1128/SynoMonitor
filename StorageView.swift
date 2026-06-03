import SwiftUI

struct StorageView: View {
    @ObservedObject var nasManager: NASNetworkManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 스토리지 영역
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("전체 스토리지 사용량")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(String(format: "%.1f TB 여유", nasManager.storageFreeTB))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 12)
                        
                        Capsule()
                            .fill(nasManager.storagePercentage > 0.9 ? Color.red : Color.green)
                            .frame(width: max(0, geometry.size.width * CGFloat(nasManager.storagePercentage)), height: 12)
                    }
                }
                .frame(height: 12)
                .animation(.easeInOut(duration: 1.0), value: nasManager.storagePercentage)
            }
            
            Divider()
            
            // 폴더별 용량 리스트
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("공유 폴더 사용량 (1일 1회 갱신)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if nasManager.isFetchingFolderSizes {
                        ProgressView().scaleEffect(0.7).frame(height: 14)
                    } else {
                        Button(action: {
                            nasManager.triggerFolderSizeScan()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if !nasManager.folderSizes.isEmpty {
                    let sortedFolders = nasManager.folderSizes.sorted { 
                        if $0.value == $1.value {
                            return $0.key < $1.key
                        }
                        return $0.value > $1.value
                    }
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 8) {
                            ForEach(sortedFolders, id: \.key) { folder in
                                HStack {
                                    Text(folder.key)
                                        .font(.body.weight(.regular))
                                    Spacer()
                                    Text(formatFolderSize(folder.value))
                                        .font(.body.monospacedDigit())
                                }
                                Divider()
                            }
                        }
                        .padding(.trailing, 8)
                    }
                } else {
                    Text(nasManager.isFetchingFolderSizes ? "폴더 스캔 중..." : "공유 폴더 용량 정보 없음")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                }
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 400)
    }
    
    private func formatFolderSize(_ bytes: Double) -> String {
        let kb = bytes / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        let tb = gb / 1024
        
        if tb >= 1.0 {
            return String(format: "%.1f TB", tb)
        } else if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.0f B", bytes)
        }
    }
}
