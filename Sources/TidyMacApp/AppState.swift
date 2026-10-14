import SwiftUI
import TidyMacCore

public enum AppNavigationItem: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case duplicates
    case apps
    case organize
    case rules
    case history
    case settings

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .overview: return localized("nav.overview")
        case .cleanup: return localized("nav.cleanup")
        case .duplicates: return localized("nav.duplicates")
        case .apps: return localized("nav.apps")
        case .organize: return localized("nav.organize")
        case .rules: return localized("nav.rules")
        case .history: return localized("nav.history")
        case .settings: return localized("nav.settings")
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: return "gauge.with.needle.fill"
        case .cleanup: return "sparkles"
        case .duplicates: return "doc.on.doc.fill"
        case .apps: return "app.badge.checkmark"
        case .organize: return "folder.badge.gearshape"
        case .rules: return "slider.horizontal.3"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var selectedNavigation: AppNavigationItem = .overview
    @Published public var isScanning: Bool = false
    @Published public var storageSummary: StorageSummary = StorageSummary()
    @Published public var scannedItems: [FileItem] = []
    @Published public var hasFullDiskAccess: Bool = false
    @Published public var freeAllowanceUsed: Int64 = 0
    @Published public var trialDaysRemaining: Int = 15

    public init() {}
}
