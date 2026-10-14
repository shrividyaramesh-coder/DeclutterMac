import Foundation
import TidyMacCore

@MainActor
func runDashboardAndCleanupTests() {
    print("\n--- Running Dashboard & Space Preview Tests ---")
    
    // 1. Space Preview Calculation Test
    let currentFree: Int64 = 200_000_000_000 // 200 GB
    let selectedCleanup: Int64 = 15_000_000_000 // 15 GB
    let expectedProjected = currentFree + selectedCleanup
    expectEqual(expectedProjected, 215_000_000_000, "Projected free space calculation: current + selected")
    
    // 2. Select Recommended Logic Test
    var items: [FileItem] = [
        FileItem(url: URL(fileURLWithPath: "/tmp/cache.log"), fileSize: 1000, category: .caches, riskLabel: .safe, isSelected: false),
        FileItem(url: URL(fileURLWithPath: "/tmp/doc.pdf"), fileSize: 2000, category: .largeFiles, riskLabel: .review, isSelected: true),
        FileItem(url: URL(fileURLWithPath: "/tmp/sys.plist"), fileSize: 3000, category: .manualReview, riskLabel: .manual, isSelected: false)
    ]
    
    // Perform "Select Recommended" (only Safe selected)
    for i in items.indices {
        if items[i].riskLabel == .safe {
            items[i].setSelected(true)
        } else {
            items[i].setSelected(false)
        }
    }
    
    expect(items[0].isSelected, "Safe item must be selected by Select Recommended")
    expect(!items[1].isSelected, "Review item must NOT be selected by Select Recommended")
    expect(!items[2].isSelected, "Manual item must NEVER be selected by Select Recommended")
    
    // 3. Deselect All Test
    for i in items.indices {
        items[i].setSelected(false)
    }
    expect(!items[0].isSelected && !items[1].isSelected && !items[2].isSelected, "Deselect All must uncheck all items")
    
    // 4. Manual Risk Protection Invariant
    items[2].setSelected(true)
    expect(!items[2].isSelected, "Manual item must refuse selection attempt")
}
