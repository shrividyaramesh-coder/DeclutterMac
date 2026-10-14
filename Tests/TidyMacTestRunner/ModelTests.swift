import Foundation
import TidyMacCore

@MainActor
func runModelTests() {
    print("\n--- Running Model & Safety Invariant Tests ---")
    
    // Risk Label Safety Invariant
    expect(RiskLabel.safe.isSelectable, "Safe risk label must be selectable")
    expect(RiskLabel.review.isSelectable, "Review risk label must be selectable")
    expect(!RiskLabel.manual.isSelectable, "Manual risk label must NEVER be selectable")
    
    // FileItem Manual Invariant
    let manualURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var item = FileItem(
        url: manualURL,
        fileSize: 1024 * 1024 * 50,
        category: .manualReview,
        riskLabel: .manual,
        isSelected: true
    )
    expect(!item.isSelected, "FileItem with manual risk must force isSelected: false")
    item.setSelected(true)
    expect(!item.isSelected, "FileItem setSelected(true) must reject selection for manual items")
    
    // Storage Summary Calculations
    let summary = StorageSummary(
        totalDiskBytes: 1_000_000_000,
        freeDiskBytes: 400_000_000,
        usedDiskBytes: 600_000_000,
        reclaimableBytes: 50_000_000,
        lifetimeReclaimedBytes: 150_000_000
    )
    expectEqual(summary.usedPercentage, 0.60, "StorageSummary usedPercentage should be 0.60")
    expectEqual(summary.reclaimablePercentage, 0.05, "StorageSummary reclaimablePercentage should be 0.05")
    expect(!summary.formattedTotal.isEmpty, "StorageSummary formattedTotal should not be empty")
}
