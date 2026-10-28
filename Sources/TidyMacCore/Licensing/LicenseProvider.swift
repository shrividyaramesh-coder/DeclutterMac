import Foundation

/// Licensing state of the application.
public enum LicenseStatus: Equatable, Sendable {
    case freeTier(bytesCleaned: Int64, allowanceBytes: Int64)
    case trial(daysRemaining: Int)
    case unlocked(licenseKey: String)
    
    public var isUnlimited: Bool {
        switch self {
        case .unlocked:
            return true
        case .trial(let days):
            return days > 0
        case .freeTier(let cleaned, let allowance):
            return cleaned < allowance
        }
    }
}

/// Protocol abstracting licensing checks, trial expiration, and lifetime purchase unlock.
public protocol LicenseProvider: Sendable {
    func currentStatus() async -> LicenseStatus
    func recordCleanedBytes(_ bytes: Int64) async
    func unlockLifetime(key: String) async -> Bool
    /// Activates a lifetime key with the payment provider; unlocks only when the key is accepted.
    func activateLifetime(key: String) async -> Result<Void, LicenseActivationError>
    func restorePurchases() async -> Bool
    func reset() async
    
    /// Returns the number of folder sorting operations performed.
    func folderSortsCount() async -> Int
    /// Returns whether the user is authorized to perform another folder sort (unlocked, or used < 2 free sorts).
    func canSortFolder() async -> Bool
    /// Records a completed folder sort operation.
    func recordFolderSort() async
}

/// Concrete local implementation of LicenseProvider with 2 GB free allowance, 15-day trial, and 2 free folder sorts.
public actor LocalLicenseProvider: LicenseProvider {
    public static let shared = LocalLicenseProvider()
    
    public static let defaultFreeAllowanceBytes: Int64 = 2 * 1024 * 1024 * 1024 // 2 GB
    public static let trialDurationDays: Int = 15
    public static let maxFreeFolderSorts: Int = 2
    
    private let cleanedBytesKey = "TidyMacCleanedBytesTotal"
    private let trialStartDateKey = "TidyMacTrialStartDate"
    private let lifetimeLicenseKey = "TidyMacLifetimeLicenseKey"
    private let folderSortsKey = "TidyMacFolderSortsCount"
    private let licenseInstanceKey = "TidyMacLicenseInstanceID"
    
    private let verifier: LicenseKeyVerifying
    private let defaults: UserDefaults
    private var cleanedBytes: Int64
    private var trialStartDate: Date
    private var lifetimeKey: String?
    /// Activation instance ID from the payment provider. A key only counts as unlocked once it has one,
    /// so keys saved by older builds (which accepted any text) must be activated again.
    private var licenseInstanceID: String?
    private var folderSorts: Int
    
    public init(verifier: LicenseKeyVerifying = DodoLicenseClient(), defaults: UserDefaults = .standard) {
        self.verifier = verifier
        self.defaults = defaults
        self.cleanedBytes = Int64(defaults.integer(forKey: cleanedBytesKey))
        self.folderSorts = defaults.integer(forKey: folderSortsKey)
        if let storedDate = defaults.object(forKey: trialStartDateKey) as? Date {
            self.trialStartDate = storedDate
        } else {
            let now = Date()
            self.trialStartDate = now
            defaults.set(now, forKey: trialStartDateKey)
        }
        self.lifetimeKey = defaults.string(forKey: lifetimeLicenseKey)
        self.licenseInstanceID = defaults.string(forKey: licenseInstanceKey)
    }
    
    private var activatedKey: String? {
        guard let key = lifetimeKey, !key.isEmpty, licenseInstanceID != nil else { return nil }
        return key
    }
    
    public func currentStatus() -> LicenseStatus {
        if let key = activatedKey {
            return .unlocked(licenseKey: key)
        }
        let elapsed = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        let daysRemaining = max(0, Self.trialDurationDays - elapsed)
        if daysRemaining > 0 {
            return .trial(daysRemaining: daysRemaining)
        }
        return .freeTier(bytesCleaned: cleanedBytes, allowanceBytes: Self.defaultFreeAllowanceBytes)
    }
    
    public func recordCleanedBytes(_ bytes: Int64) {
        cleanedBytes += bytes
        defaults.set(cleanedBytes, forKey: cleanedBytesKey)
    }
    
    public func folderSortsCount() -> Int {
        folderSorts
    }
    
    public func canSortFolder() -> Bool {
        if activatedKey != nil {
            return true
        }
        return folderSorts < Self.maxFreeFolderSorts
    }
    
    public func recordFolderSort() {
        folderSorts += 1
        defaults.set(folderSorts, forKey: folderSortsKey)
    }
    
    public func unlockLifetime(key: String) async -> Bool {
        if case .success = await activateLifetime(key: key) { return true }
        return false
    }
    
    public func activateLifetime(key: String) async -> Result<Void, LicenseActivationError> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyKey) }
        do {
            let instanceID = try await verifier.activate(key: trimmed, deviceName: Self.deviceName)
            storeLicense(key: trimmed, instanceID: instanceID)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    /// Re-checks the saved key with the payment provider. Stays unlocked when offline; locks only when
    /// the provider says the key or this Mac's activation is no longer valid.
    public func restorePurchases() async -> Bool {
        guard let key = lifetimeKey, !key.isEmpty else { return false }
        guard let instanceID = licenseInstanceID else {
            return await unlockLifetime(key: key)
        }
        do {
            let valid = try await verifier.validate(key: key, instanceID: instanceID)
            if !valid { storeLicense(key: nil, instanceID: nil) }
            return valid
        } catch {
            return true
        }
    }
    
    public func reset() {
        cleanedBytes = 0
        folderSorts = 0
        trialStartDate = Date()
        storeLicense(key: nil, instanceID: nil)
        defaults.removeObject(forKey: cleanedBytesKey)
        defaults.removeObject(forKey: folderSortsKey)
        defaults.removeObject(forKey: trialStartDateKey)
    }
    
    private func storeLicense(key: String?, instanceID: String?) {
        lifetimeKey = key
        licenseInstanceID = instanceID
        defaults.set(key, forKey: lifetimeLicenseKey)
        defaults.set(instanceID, forKey: licenseInstanceKey)
    }
    
    private static var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }
}
