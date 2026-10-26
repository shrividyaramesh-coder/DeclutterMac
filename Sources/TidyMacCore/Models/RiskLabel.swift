import Foundation

/// Risk classification for scanned items indicating cleaning safety.
public enum RiskLabel: String, Sendable, Codable, CaseIterable, Identifiable {
    case safe
    case review
    case manual

    public var id: String { rawValue }

    /// Whether this risk level is permissible for automated or batch selection.
    /// Invariant: `manual` items can NEVER be selected or cleaned by automated routines.
    public var isSelectable: Bool {
        switch self {
        case .safe, .review:
            return true
        case .manual:
            return false
        }
    }

    /// User-facing display name.
    public var title: String {
        switch self {
        case .safe:
            return "Safe"
        case .review:
            return "Review"
        case .manual:
            return "Manual"
        }
    }

    /// Plain language explanation of risk level.
    public var explanation: String {
        switch self {
        case .safe:
            return "Safe to remove. Temporary cache, log, or installer with no personal data."
        case .review:
            return "Review recommended. May contain personal documents, archives, or screenshots."
        case .manual:
            return "Visible for information only. Protected or sensitive item that Declutter Mac will never automatically remove."
        }
    }

    /// Recommended SF Symbol icon.
    public var systemImage: String {
        switch self {
        case .safe:
            return "checkmark.shield.fill"
        case .review:
            return "exclamationmark.triangle.fill"
        case .manual:
            return "lock.shield.fill"
        }
    }
}
