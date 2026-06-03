import SwiftUI

struct PieSlice: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
    let startFraction: CGFloat
    let endFraction: CGFloat
}

struct HoverableFolderRow: View {
    let folderName: String
    let folderSize: Double
    let totalBytes: Double
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Text(folderName)
                .font(.body.weight(.regular))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if folderSize == -1.0 {
                    Text("산출 지연됨 (Timeout)")
                        .font(.caption2)
                        .foregroundColor(.red)
                } else {
                    Text(folderSize.formattedBytes)
                        .font(.body.monospacedDigit())
                    if totalBytes > 0 {
                        let pct = (folderSize / totalBytes) * 100.0
                        Text(String(format: "%.1f%%", pct))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(isHovered ? .primary.opacity(0.8) : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("전체 스토리지 사용량")
                .accessibilityValue("\(Int(nasManager.storagePercentage * 100)) 퍼센트")
            }
            
            if nasManager.volumes.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("볼륨별 사용량")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                    ForEach(nasManager.volumes) { vol in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(vol.name)
                                    .font(.caption2.weight(.medium))
                                Spacer()
                                Text(String(format: "%.0f%% (%.1f / %.1f TB)", vol.percentage * 100, vol.usedBytes / 1_099_511_627_776.0, vol.totalBytes / 1_099_511_627_776.0))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(vol.percentage > 0.9 ? .red : .secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 6)
                                    Capsule()
                                        .fill(vol.percentage > 0.9 ? Color.red : (vol.percentage > 0.7 ? Color.orange : Color.green))
                                        .frame(width: max(0, geo.size.width * CGFloat(vol.percentage)), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(.top, 4)
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
                                HoverableFolderRow(
                                    folderName: folder.key,
                                    folderSize: folder.value,
                                    totalBytes: nasManager.storageTotalBytes
                                )
                                Divider().padding(.horizontal, 8)
                            }
                            
                            // 원형 그래프
                            if !chartSlices.isEmpty {
                                VStack(alignment: .center, spacing: 12) {
                                    Text("용량 분포 그래프")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 8)
                                        .padding(.horizontal, 4)
                                    
                                    HStack(spacing: 20) {
                                        ZStack {
                                            // Background shadow for depth
                                            Circle()
                                                .fill(Color.primary.opacity(0.02))
                                                .frame(width: 100, height: 100)
                                                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                                            
                                            ForEach(chartSlices) { slice in
                                                Circle()
                                                    .trim(from: slice.startFraction, to: slice.endFraction)
                                                    .stroke(slice.color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                                                    .rotationEffect(.degrees(-90))
                                            }
                                        }
                                        .frame(width: 100, height: 100)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("공유 폴더별 용량 파이 차트")
                                        
                                        LazyVGrid(columns: [GridItem(.flexible())], alignment: .leading, spacing: 8) {
                                            ForEach(chartSlices) { slice in
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(slice.color)
                                                        .frame(width: 8, height: 8)
                                                    Text(slice.name)
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundColor(.primary.opacity(0.8))
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .padding(.bottom, 8)
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
        .frame(width: 320)
    }
    
    private var chartSlices: [PieSlice] {
        guard nasManager.storageTotalBytes > 0 else { return [] }
        var slices: [PieSlice] = []
        let total = nasManager.storageTotalBytes
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .yellow, .cyan, .mint]
        
        var currentFraction: CGFloat = 0
        var sumFolders: Double = 0
        let sortedFolders = nasManager.folderSizes.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        
        for (i, folder) in sortedFolders.enumerated() {
            let fraction = CGFloat(folder.value / total)
            slices.append(PieSlice(name: folder.key, value: folder.value, color: colors[i % colors.count], startFraction: currentFraction, endFraction: currentFraction + fraction))
            currentFraction += fraction
            sumFolders += folder.value
        }
        
        let used = nasManager.storagePercentage * total
        let other = used - sumFolders
        if other > 0 {
            let fraction = CGFloat(other / total)
            slices.append(PieSlice(name: "기타 (시스템 등)", value: other, color: .gray.opacity(0.6), startFraction: currentFraction, endFraction: currentFraction + fraction))
            currentFraction += fraction
        }
        
        let free = total - used
        if free > 0 {
            let fraction = CGFloat(free / total)
            slices.append(PieSlice(name: "여유 공간", value: free, color: .secondary.opacity(0.2), startFraction: currentFraction, endFraction: currentFraction + fraction))
        }
        
        return slices
    }
}
