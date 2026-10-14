import Foundation

/// Licensing state of the application.
public enum LicenseStatus: Equatable, Sendable {
    case freeTier(bytesCleaned: Int64, allowanceBytes: Int64)
    case trial(daysRemaining: Int)
    case unlocked(licenseKey: String)
    
    public var isUnlimited: Bool {
        switch self {
        case .unlocked: return true
        case .trial: return true
        case .freeTier(let cleaned, let allowance): return cleaned < allowance
        }
    }
}

/// Protocol abstracting licensing checks, trial expiration, and lifetime purchase unlock.
public protocol LicenseProvider: Sendable {
    func currentStatus() async -> LicenseStatus
    func recordCleanedBytes(_ bytes: Int64) async
    func unlockLifetime(key: String) async -> Bool
    func restorePurchases() async -> Bool
    func reset() async
}

/// Concrete local implementation of LicenseProvider with 2 GB free allowance and 15-day trial.
public actor LocalLicenseProvider: LicenseProvider {
    public static let shared = LocalLicenseProvider()
    
    public static let defaultFreeAllowanceBytes: Int64 = 2 * 1024 * 1024 * 1024 // 2 GB
    public static let trialDurationDays: Int = 15
    
    private let cleanedBytesKey = "TidyMacCleanedBytesTotal"
    private let trialStartDateKey = "TidyMacTrialStartDate"
    private let lifetimeLicenseKey = "TidyMacLifetimeLicenseKey"
    
    private var cleanedBytes: Int64
    private var trialStartDate: Date
    private var lifetimeKey: String?
    
    public init() {
        self.cleanedBytes = Int64(UserDefaults.standard.integer(forKey: cleanedBytesKey))
        if let storedDate = UserDefaults.standard.object(forKey: trialStartDateKey) as? Date {
            self.trialStartDate = storedDate
        } else {
            let now = Date()
            self.trialStartDate = now
            UserDefaults.standard.set(now, forKey: trialStartDateKey)
        }
        self.lifetimeKey = UserDefaults.standard.string(forKey: lifetimeLicenseKey)
    }
    
    public func currentStatus() -> LicenseStatus {
        if let key = lifetimeKey, !key.isEmpty {
            return .unlocked(licenseKey: key)
        }
        
        // Check 15-day trial
        let daysElapsed = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        let daysRemaining = max(0, Self.trialDurationDays - daysElapsed)
        
        if daysRemaining > 0 {
            return .trial(daysRemaining: daysRemaining)
        }
        
        // Revert to free tier allowance
        return .freeTier(bytesCleaned: cleanedBytes, allowanceBytes: Self.defaultFreeAllowanceBytes)
    }
    
    public func recordCleanedBytes(_ bytes: Int64) {
        cleanedBytes += bytes
        UserDefaults.standard.set(cleanedBytes, forKey: cleanedBytesKey)
    }
    
    public func unlockLifetime(key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        self.lifetimeKey = trimmed
        UserDefaults.standard.set(trimmed, forKey: lifetimeLicenseKey)
        return true
    }
    
    public func restorePurchases() -> Bool {
        if let key = UserDefaults.standard.string(forKey: lifetimeLicenseKey), !key.isEmpty {
            self.lifetimeKey = key
            return true
        }
        return false
    }
    
    public func reset() {
        cleanedBytes = 0
        trialStartDate = Date()
        lifetimeKey = nil
        UserDefaults.standard.removeObject(forKey: cleanedBytesKey)
        UserDefaults.standard.removeObject(forKey: trialStartDateKey)
        UserDefaults.standard.removeObject(forKey: lifetimeLicenseKey)
    }
}
