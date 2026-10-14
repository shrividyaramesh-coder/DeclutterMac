import SwiftUI
import TidyMacCore

public struct DiskUsageBar: View {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let reclaimableBytes: Int64
    public let freeBytes: Int64

    public init(totalBytes: Int64, usedBytes: Int64, reclaimableBytes: Int64, freeBytes: Int64) {
        self.totalBytes = max(1, totalBytes)
        self.usedBytes = max(0, usedBytes)
        self.reclaimableBytes = max(0, reclaimableBytes)
        self.freeBytes = max(0, freeBytes)
    }

    private var usedRatio: Double {
        Double(max(0, usedBytes - reclaimableBytes)) / Double(totalBytes)
    }

    private var reclaimableRatio: Double {
        Double(reclaimableBytes) / Double(totalBytes)
    }

    private var freeRatio: Double {
        Double(freeBytes) / Double(totalBytes)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    // Non-reclaimable Used Space
                    Rectangle()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: max(0, geometry.size.width * usedRatio))
                    
                    // Reclaimable Space
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: max(0, geometry.size.width * reclaimableRatio))
                    
                    // Free Space
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(maxWidth: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 24)

            // Legend
            HStack(spacing: 20) {
                legendItem(title: "System & Apps", bytes: max(0, usedBytes - reclaimableBytes), color: Color.primary.opacity(0.7))
                legendItem(title: localized("dashboard.reclaimable_now"), bytes: reclaimableBytes, color: Color.orange)
                legendItem(title: localized("preview.current_free"), bytes: freeBytes, color: Color.secondary.opacity(0.4))
                Spacer()
                Text("Total: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legendItem(title: String, bytes: Int64, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.caption)
                .bold()
        }
    }
}
