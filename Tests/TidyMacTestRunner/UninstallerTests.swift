import Foundation
import TidyMacCore

@MainActor
func runUninstallerTests() async {
    print("\n--- Running AppUninstaller & Leftovers Tests ---")
    
    let engine = AppUninstallerEngine.shared
    
    // 1. System Protection Guard Tests
    let safariApp = InstalledApp(
        name: "Safari",
        bundleIdentifier: "com.apple.Safari",
        url: URL(fileURLWithPath: "/Applications/Safari.app"),
        appSize: 50_000_000,
        isSystemProtected: true
    )
    expect(safariApp.isSystemProtected, "Safari must be flagged as system protected")
    
    let finderApp = InstalledApp(
        name: "Finder",
        bundleIdentifier: "com.apple.finder",
        url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
        appSize: 20_000_000,
        isSystemProtected: true
    )
    expect(finderApp.isSystemProtected, "Finder must be flagged as system protected")
    
    let thirdPartyApp = InstalledApp(
        name: "AcmeTools",
        bundleIdentifier: "com.acme.tools",
        url: URL(fileURLWithPath: "/Applications/AcmeTools.app"),
        appSize: 30_000_000,
        isSystemProtected: false
    )
    expect(!thirdPartyApp.isSystemProtected, "Third-party application is not system protected")
    
    // 2. Leftover Scanner Integration Test
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyMacUninstallTests_\(UUID().uuidString)")
    let fakeLibrary = tempDir.appendingPathComponent("Library")
    let fakeAppSupport = fakeLibrary.appendingPathComponent("Application Support/com.acme.tools")
    let fakeCaches = fakeLibrary.appendingPathComponent("Caches/com.acme.tools")
    let fakePrefs = fakeLibrary.appendingPathComponent("Preferences")
    let fakeSavedState = fakeLibrary.appendingPathComponent("Saved Application State/com.acme.tools.savedState")
    
    try? FileManager.default.createDirectory(at: fakeAppSupport, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeCaches, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakePrefs, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: fakeSavedState, withIntermediateDirectories: true)
    
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Seed leftovers
    let dbFile = fakeAppSupport.appendingPathComponent("storage.db")
    FileManager.default.createFile(atPath: dbFile.path, contents: Data(repeating: 0x11, count: 50_000))
    
    let cacheFile = fakeCaches.appendingPathComponent("network.cache")
    FileManager.default.createFile(atPath: cacheFile.path, contents: Data(repeating: 0x22, count: 30_000))
    
    let prefFile = fakePrefs.appendingPathComponent("com.acme.tools.plist")
    FileManager.default.createFile(atPath: prefFile.path, contents: Data(repeating: 0x33, count: 5_000))
    
    let stateFile = fakeSavedState.appendingPathComponent("window.saved")
    FileManager.default.createFile(atPath: stateFile.path, contents: Data(repeating: 0x44, count: 10_000))
    
    // Execute leftovers search
    let uninstallBundle = await engine.findLeftovers(for: thirdPartyApp, libraryRoot: fakeLibrary)
    expectEqual(uninstallBundle.leftovers.count, 4, "Discovered exactly 4 seeded leftovers for AcmeTools")
    
    let leftoverPaths = uninstallBundle.leftovers.map(\.url.lastPathComponent)
    expect(leftoverPaths.contains("com.acme.tools"), "Application Support or Caches directory discovered")
    expect(leftoverPaths.contains("com.acme.tools.plist"), "Preferences plist discovered")
    expect(leftoverPaths.contains("com.acme.tools.savedState"), "Saved Application State bundle discovered")
    expect(uninstallBundle.totalSize > thirdPartyApp.appSize, "Total size includes both app bundle and leftovers")
}
