import Foundation

/// Evaluates file risk classification based on category, age, size, and location.
public struct RiskEvaluator: Sendable {
    /// Minimum age (in seconds) for installers to be classified as Safe (default: 7 days).
    public static let safeInstallerAgeSeconds: TimeInterval = 7 * 24 * 60 * 60

    /// Minimum age (in seconds) for screenshots to be flagged for review (default: 30 days).
    public static let reviewScreenshotAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    /// Evaluates the risk label for a candidate file.
    public static func evaluateRisk(
        category: ScanCategory,
        url: URL,
        fileSize: Int64,
        createdDate: Date,
        lastOpenedDate: Date? = nil
    ) -> RiskLabel {
        let now = Date()
        let age = now.timeIntervalSince(createdDate)
        let path = url.path(percentEncoded: false)

        // 1. Manual Invariant: Any item flagged for manual review or located in sensitive paths
        if category == .manualReview ||
           path.contains("/Keychains/") ||
           path.contains("/Preferences/com.apple.") ||
           path.hasSuffix(".plist") && path.contains("/Preferences/") {
            return .manual
        }

        // 2. Safe Items: Temporary caches, ephemeral logs, Trash contents, and old installers
        switch category {
        case .caches, .logs, .trash, .browserCaches:
            return .safe

        case .oldDownloads:
            // Installers older than 7 days are Safe to remove; newer ones require Review
            if age >= safeInstallerAgeSeconds {
                return .safe
            } else {
                return .review
            }

        case .developerCaches:
            // Developer DerivedData is safe for developers to clear, but marked review so user can opt-in
            return .review

        case .screenshots:
            // Screenshots are personal media, so they default to Review
            return .review

        case .largeFiles:
            // Large files default to Review so user verifies they are not active work documents
            return .review

        case .messagingMedia:
            return .review

        case .duplicates:
            return .review

        case .appLeftovers:
            // Leftovers of uninstalled apps are Review
            return .review

        case .manualReview:
            return .manual
        }
    }
}
