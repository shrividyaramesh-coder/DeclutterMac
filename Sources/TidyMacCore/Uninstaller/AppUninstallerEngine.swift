import Foundation

/// Engine discovering installed macOS applications, protecting system apps, and scanning leftovers.
public actor AppUninstallerEngine {
    public static let shared = AppUninstallerEngine()

    private let protectedBundlePrefixes: Set<String> = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.systempreferences",
        "com.apple.AppStore",
        "com.apple.Terminal",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility",
        "com.apple.keychainaccess"
    ]

    public init() {}

    /// Discovers all installed application bundles in standard or provided directories.
    public func listInstalledApps(searchDirectories: [URL]? = nil) -> [InstalledApp] {
        let fileManager = FileManager.default
        let searchRoots: [URL] = searchDirectories ?? [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var apps: [InstalledApp] = []

        for root in searchRoots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isPackageKey], options: [.skipsHiddenFiles]) else {
                continue
            }

            for item in contents where item.pathExtension == "app" {
                let app = inspectAppBundle(at: item)
                apps.append(app)
            }
        }

        return apps.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    /// Finds related leftover files and directories for a given application.
    public func findLeftovers(for app: InstalledApp, libraryRoot: URL? = nil) -> AppUninstallBundle {
        let fileManager = FileManager.default
        let library = libraryRoot ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library")

        var leftovers: [FileItem] = []
        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.name

        // Define search locations
        let searchPaths: [(folder: String, isExactPlist: Bool, isSavedState: Bool)] = [
            ("Application Support", false, false),
            ("Caches", false, false),
            ("Containers", false, false),
            ("Logs", false, false),
            ("HTTPStorages", false, false),
            ("Preferences", true, false),
            ("Saved Application State", false, true)
        ]

        for entry in searchPaths {
            let targetDir = library.appendingPathComponent(entry.folder)
            guard fileManager.fileExists(atPath: targetDir.path) else { continue }

            if entry.isExactPlist {
                // Preferences: look for <bundleId>.plist
                if !bundleId.isEmpty {
                    let plistURL = targetDir.appendingPathComponent("\(bundleId).plist")
                    if fileManager.fileExists(atPath: plistURL.path) {
                        let size = calculateSize(of: plistURL)
                        leftovers.append(FileItem(url: plistURL, fileSize: size, category: .appLeftovers, riskLabel: .review, isSelected: true))
                    }
                }
            } else if entry.isSavedState {
                // Saved Application State: <bundleId>.savedState
                if !bundleId.isEmpty {
                    let stateURL = targetDir.appendingPathComponent("\(bundleId).savedState")
                    if fileManager.fileExists(atPath: stateURL.path) {
                        let size = calculateSize(of: stateURL)
                        leftovers.append(FileItem(url: stateURL, fileSize: size, category: .appLeftovers, riskLabel: .review, isSelected: true))
                    }
                }
            } else {
                // Directories matched by bundle ID or app name
                if !bundleId.isEmpty {
                    let bundleCandidate = targetDir.appendingPathComponent(bundleId)
                    if fileManager.fileExists(atPath: bundleCandidate.path) {
                        let size = calculateSize(of: bundleCandidate)
                        leftovers.append(FileItem(url: bundleCandidate, fileSize: size, category: .appLeftovers, riskLabel: .review, isSelected: true))
                    }
                }

                let nameCandidate = targetDir.appendingPathComponent(appName)
                if fileManager.fileExists(atPath: nameCandidate.path) && nameCandidate.path != targetDir.appendingPathComponent(bundleId).path {
                    let size = calculateSize(of: nameCandidate)
                    leftovers.append(FileItem(url: nameCandidate, fileSize: size, category: .appLeftovers, riskLabel: .review, isSelected: true))
                }
            }
        }

        return AppUninstallBundle(app: app, leftovers: leftovers)
    }

    /// Inspects an `.app` bundle, reading Info.plist and computing total bundle size.
    private func inspectAppBundle(at url: URL) -> InstalledApp {
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                   bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                   url.deletingPathExtension().lastPathComponent
        let bundleId = bundle?.bundleIdentifier
        let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ??
                      bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        let path = url.path(percentEncoded: false)
        let isProtected = isAppProtected(path: path, bundleIdentifier: bundleId)
        let size = calculateSize(of: url)

        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return InstalledApp(
            name: name,
            bundleIdentifier: bundleId,
            version: version,
            url: url,
            appSize: size,
            lastOpenedDate: modDate,
            isSystemProtected: isProtected
        )
    }

    /// Determines if an app is a protected system application.
    private func isAppProtected(path: String, bundleIdentifier: String?) -> Bool {
        if path.hasPrefix("/System/") || path.hasPrefix("/Applications/Utilities") {
            return true
        }
        if let id = bundleIdentifier {
            if protectedBundlePrefixes.contains(id) {
                return true
            }
        }
        if path.contains("Safari.app") || path.contains("Finder.app") || path.contains("System Settings.app") {
            return true
        }
        return false
    }

    /// Recursively calculates the byte size of a file or bundle directory.
    private func calculateSize(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            return Int64((try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }

        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsPackageDescendants]) else {
            return 0
        }

        while let file = enumerator.nextObject() as? URL {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
