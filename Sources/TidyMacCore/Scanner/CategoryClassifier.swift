import Foundation

/// Analyzes file paths, names, and metadata to classify files into scan categories.
public struct CategoryClassifier: Sendable {
    private static let installerExtensions: Set<String> = [
        "dmg", "pkg", "iso", "appinstaller"
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"
    ]

    private static let screenshotPrefixes: [String] = [
        "Screen Shot", "Screenshot", "Capture d’écran", "Bildschirmfoto", "スクリーンショット", "스크린샷", "截屏", "螢幕截圖", "Captura de pantalla"
    ]

    /// Categorizes a file based on its URL, size, dates, and attributes.
    public static func classify(
        url: URL,
        fileSize: Int64,
        createdDate: Date,
        lastOpenedDate: Date? = nil
    ) -> ScanCategory {
        let path = url.path(percentEncoded: false)
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        // 1. Trash Can
        if path.contains("/.Trash/") || path.hasSuffix("/.Trash") {
            return .trash
        }

        // 2. Developer caches
        if path.contains("Library/Developer/Xcode/DerivedData") ||
           path.contains("Library/Developer/Xcode/Archives") ||
           path.contains("Library/Developer/CoreSimulator/Caches") {
            return .developerCaches
        }

        // 3. Browser caches
        if path.contains("Library/Caches/Google") ||
           path.contains("Library/Caches/com.apple.Safari") ||
           path.contains("Library/Caches/company.thebrowser.Browser") || // Arc
           path.contains("Library/Caches/org.mozilla.firefox") ||
           path.contains("Library/Caches/com.brave.Browser") ||
           path.contains("Library/Caches/BraveSoftware") ||
           path.contains("Library/Caches/com.microsoft.edgemac") {
            return .browserCaches
        }

        // 4. Messaging media caches
        if path.contains("Library/Caches/com.tinyspeck.slackmacgap") ||
           path.contains("Library/Caches/ru.keepcoder.Telegram") ||
           path.contains("Library/Caches/net.whatsapp.WhatsApp") ||
           path.contains("Library/Caches/com.hnc.Discord") ||
           path.contains("Library/Caches/com.microsoft.teams2") ||
           path.contains("Library/Caches/ms-teams") {
            return .messagingMedia
        }

        // 4b. Creative and work apps caches (video, design, 3D, and audio)
        if path.contains("Library/Caches/Adobe") ||
           path.contains("Library/Application Support/Adobe/Common/Media Cache Files") ||
           path.contains("Library/Caches/com.apple.FinalCut") ||
           path.contains("Library/Caches/com.figma.Desktop") ||
           path.contains("Library/Caches/com.bohemiancoding.sketch3") ||
           path.contains("Library/Caches/blender") ||
           path.contains("Library/Caches/com.canva.CanvaDesktop") {
            return .caches
        }

        // 5. General logs
        if path.contains("/Library/Logs/") || ext == "log" {
            return .logs
        }

        // 6. General user caches
        if path.contains("/Library/Caches/") {
            return .caches
        }

        // 7. Screenshots
        if isScreenshot(filename: filename, url: url) {
            return .screenshots
        }

        // 8. Old Installers in Downloads or general folders
        if installerExtensions.contains(ext) || (archiveExtensions.contains(ext) && path.contains("/Downloads/")) {
            return .oldDownloads
        }

        // 9. App leftovers in Application Support or Containers
        if path.contains("/Library/Application Support/") || path.contains("/Library/Containers/") {
            return .appLeftovers
        }

        // 10. Large files (> 100 MB)
        if fileSize >= 100 * 1024 * 1024 {
            return .largeFiles
        }

        return .manualReview
    }

    /// Determines if a file is a screenshot based on name pattern or metadata.
    public static func isScreenshot(filename: String, url: URL? = nil) -> Bool {
        for prefix in screenshotPrefixes {
            if filename.hasPrefix(prefix) {
                return true
            }
        }
        // Check for common camera capture suffix
        if filename.hasPrefix("CleanShot") || filename.hasPrefix("Shot_") {
            return true
        }
        return false
    }
}
