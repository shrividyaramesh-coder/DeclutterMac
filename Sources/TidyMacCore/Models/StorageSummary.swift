import Foundation

/// High-level disk storage breakdown and reclaimable space metrics.
public struct StorageSummary: Sendable, Codable, Equatable {
    public let totalDiskBytes: Int64
    public let freeDiskBytes: Int64
    public let usedDiskBytes: Int64
    public let reclaimableBytes: Int64
    public let lifetimeReclaimedBytes: Int64
    public let categoryBreakdown: [ScanCategory: Int64]

    public init(
        totalDiskBytes: Int64 = 0,
        freeDiskBytes: Int64 = 0,
        usedDiskBytes: Int64 = 0,
        reclaimableBytes: Int64 = 0,
        lifetimeReclaimedBytes: Int64 = 0,
        categoryBreakdown: [ScanCategory: Int64] = [:]
    ) {
        self.totalDiskBytes = totalDiskBytes
        self.freeDiskBytes = freeDiskBytes
        self.usedDiskBytes = usedDiskBytes
        self.reclaimableBytes = reclaimableBytes
        self.lifetimeReclaimedBytes = lifetimeReclaimedBytes
        self.categoryBreakdown = categoryBreakdown
    }

    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalDiskBytes, countStyle: .file)
    }

    public var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: freeDiskBytes, countStyle: .file)
    }

    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedDiskBytes, countStyle: .file)
    }

    public var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: reclaimableBytes, countStyle: .file)
    }

    public var formattedLifetimeReclaimed: String {
        ByteCountFormatter.string(fromByteCount: lifetimeReclaimedBytes, countStyle: .file)
    }

    public var usedPercentage: Double {
        guard totalDiskBytes > 0 else { return 0.0 }
        return Double(usedDiskBytes) / Double(totalDiskBytes)
    }

    public var reclaimablePercentage: Double {
        guard totalDiskBytes > 0 else { return 0.0 }
        return Double(reclaimableBytes) / Double(totalDiskBytes)
    }
}
