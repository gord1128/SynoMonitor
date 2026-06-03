import Foundation

extension Double {
    var formattedBytes: String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = self
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return unitIndex == 0 ? String(format: "%.0f %@", value, units[unitIndex])
                              : String(format: "%.1f %@", value, units[unitIndex])
    }
}
