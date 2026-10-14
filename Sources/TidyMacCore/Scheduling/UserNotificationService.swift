import Foundation
import UserNotifications

/// Handles posting local macOS notifications when scheduled cleanups complete.
public struct UserNotificationService: Sendable {
    public static let shared = UserNotificationService()
    
    public init() {}
    
    /// Requests notification authorization from macOS.
    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    /// Posts a cleanup notification summary to macOS Notification Center.
    public func postCleanupSummary(filesCleaned: Int, bytesReclaimed: Int64) {
        guard filesCleaned > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Tidy Mac Scheduled Cleanup Complete"
        let formattedSize = ByteCountFormatter.string(fromByteCount: bytesReclaimed, countStyle: .file)
        content.body = "Reclaimed \(formattedSize) across \(filesCleaned) files. Tap to view details or undo."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to dispatch notification: \(error)")
            }
        }
    }
}
