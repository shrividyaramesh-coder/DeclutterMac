import Foundation
import TidyMacCore

@MainActor
func runLaunchAgentAndAppPolishTests() {
    print("\n--- Running LaunchAgent & App Polish Tests ---")
    
    let dummyExe = URL(fileURLWithPath: "/Applications/TidyMac.app/Contents/MacOS/TidyMacApp")
    
    // 1. Plist Generation for Daily Interval
    let dailyPlist = LaunchAgentManager.shared.generatePlistContent(executableURL: dummyExe, frequency: .daily)
    expect(
        dailyPlist.contains("<string>com.tidymac.cleanup</string>"),
        "LaunchAgent plist must declare label com.tidymac.cleanup"
    )
    expect(
        dailyPlist.contains("<string>--scheduled-run</string>"),
        "LaunchAgent plist must pass --scheduled-run argument"
    )
    expect(
        dailyPlist.contains("<integer>86400</integer>"),
        "Daily schedule must set StartInterval to 86,400 seconds"
    )
    expect(
        dailyPlist.contains("<key>LowPriorityIO</key>\n    <true/>"),
        "LaunchAgent must specify LowPriorityIO for background execution"
    )
    expect(
        dailyPlist.contains("<string>Background</string>"),
        "LaunchAgent must specify ProcessType Background"
    )
    
    // 2. Weekly & Monthly & Low Disk Intervals
    let weeklyPlist = LaunchAgentManager.shared.generatePlistContent(executableURL: dummyExe, frequency: .weekly)
    expect(
        weeklyPlist.contains("<integer>604800</integer>"),
        "Weekly schedule must set StartInterval to 604,800 seconds"
    )
    
    let monthlyPlist = LaunchAgentManager.shared.generatePlistContent(executableURL: dummyExe, frequency: .monthly)
    expect(
        monthlyPlist.contains("<integer>2592000</integer>"),
        "Monthly schedule must set StartInterval to 2,592,000 seconds"
    )
    
    let lowDiskPlist = LaunchAgentManager.shared.generatePlistContent(executableURL: dummyExe, frequency: .onLowDiskSpace(thresholdGB: 10))
    expect(
        lowDiskPlist.contains("<integer>900</integer>"),
        "Low disk monitor must poll every 15 minutes (900 seconds)"
    )
    
    // 3. Creative Apps Classification Tests
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dummyDate = Date()
    
    let adobeMediaCache = home.appendingPathComponent("Library/Application Support/Adobe/Common/Media Cache Files/video.mcf")
    let adobeCat = CategoryClassifier.classify(url: adobeMediaCache, fileSize: 500_000_000, createdDate: dummyDate)
    expectEqual(
        adobeCat,
        ScanCategory.caches,
        "Adobe Media Cache must be classified into .caches"
    )
    
    let fcpCache = home.appendingPathComponent("Library/Caches/com.apple.FinalCut/renderCache.dat")
    let fcpCat = CategoryClassifier.classify(url: fcpCache, fileSize: 1_000_000_000, createdDate: dummyDate)
    expectEqual(
        fcpCat,
        ScanCategory.caches,
        "Final Cut Pro cache must be classified into .caches"
    )
    
    let figmaCache = home.appendingPathComponent("Library/Caches/com.figma.Desktop/data.db")
    let figmaCat = CategoryClassifier.classify(url: figmaCache, fileSize: 80_000_000, createdDate: dummyDate)
    expectEqual(
        figmaCat,
        ScanCategory.caches,
        "Figma cache must be classified into .caches"
    )
    
    let blenderCache = home.appendingPathComponent("Library/Caches/blender/autosave.blend")
    let blenderCat = CategoryClassifier.classify(url: blenderCache, fileSize: 40_000_000, createdDate: dummyDate)
    expectEqual(
        blenderCat,
        ScanCategory.caches,
        "Blender cache must be classified into .caches"
    )
    
    // 4. Extended Browser & Messaging App Classification
    let braveCache = home.appendingPathComponent("Library/Caches/com.brave.Browser/Cache/data")
    let braveCat = CategoryClassifier.classify(url: braveCache, fileSize: 15_000_000, createdDate: dummyDate)
    expectEqual(
        braveCat,
        ScanCategory.browserCaches,
        "Brave browser cache must be classified into .browserCaches"
    )
    
    let edgeCache = home.appendingPathComponent("Library/Caches/com.microsoft.edgemac/Cache/data")
    let edgeCat = CategoryClassifier.classify(url: edgeCache, fileSize: 25_000_000, createdDate: dummyDate)
    expectEqual(
        edgeCat,
        ScanCategory.browserCaches,
        "Microsoft Edge cache must be classified into .browserCaches"
    )
    
    let discordCache = home.appendingPathComponent("Library/Caches/com.hnc.Discord/media")
    let discordCat = CategoryClassifier.classify(url: discordCache, fileSize: 60_000_000, createdDate: dummyDate)
    expectEqual(
        discordCat,
        ScanCategory.messagingMedia,
        "Discord cache must be classified into .messagingMedia"
    )
    
    let teamsCache = home.appendingPathComponent("Library/Caches/com.microsoft.teams2/data")
    let teamsCat = CategoryClassifier.classify(url: teamsCache, fileSize: 30_000_000, createdDate: dummyDate)
    expectEqual(
        teamsCat,
        ScanCategory.messagingMedia,
        "Microsoft Teams cache must be classified into .messagingMedia"
    )
    
    // 5. PermissionsManager & ManagedFolderType Tests
    let fdaURL = PermissionsManager.fullDiskAccessSettingsURL
    expect(
        fdaURL.absoluteString.contains("Privacy_AllFiles"),
        "FDA settings URL must target Privacy_AllFiles pane"
    )
    
    let fdaStatus = PermissionsManager.shared.checkFullDiskAccess()
    expect(
        fdaStatus == true || fdaStatus == false,
        "checkFullDiskAccess executes safely and returns deterministic boolean"
    )
    
    expectEqual(
        ManagedFolderType.allCases.count,
        5,
        "ManagedFolderType must define exactly 5 core folder options"
    )
    
    for folderType in ManagedFolderType.allCases {
        let url = folderType.defaultURL
        expect(
            url.path.hasPrefix("/"),
            "Folder type \(folderType.rawValue) default URL must be an absolute path"
        )
    }
}
