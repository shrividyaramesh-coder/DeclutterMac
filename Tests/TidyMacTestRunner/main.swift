import Foundation
import TidyMacCore

print("=========================================")
print("🚀 Running Tidy Mac Automated Test Suite")
print("=========================================")

runModelTests()
runLocalizationTests()
await runSafetyTests()
await runFileAccessTests()
await runScannerTests()
runDashboardAndCleanupTests()
await runUndoJournalTests()
await runDuplicateTests()

print("\n=========================================")
if TestHarness.shared.totalTestFailures.isEmpty {
    print("🎉 ALL \(TestHarness.shared.totalTestsRun) TESTS PASSED SUCCESSFULLY!")
    print("=========================================")
    exit(0)
} else {
    print("🚨 \(TestHarness.shared.totalTestFailures.count) OF \(TestHarness.shared.totalTestsRun) TESTS FAILED!")
    for failure in TestHarness.shared.totalTestFailures {
        print("   - \(failure)")
    }
    print("=========================================")
    exit(1)
}
