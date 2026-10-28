import Foundation
import TidyMacCore

@MainActor
func runLicenseActivationTests() async {
    print("\n--- Running License Key Activation Tests ---")

    let purchasedKey = "DODO-PURCHASED-KEY"

    // 1. Made-up keys no longer unlock the app
    let provider = makeTestLicenseProvider(StubLicenseVerifier(validKeys: [purchasedKey]))
    expectEqual(failure(of: await provider.activateLifetime(key: "abc")), .keyNotFound, "A made-up key is rejected")
    expect(!(await provider.currentStatus().isUnlockedLifetime), "A rejected key does not unlock")
    expectEqual(failure(of: await provider.activateLifetime(key: "   ")), .emptyKey, "A blank key is rejected without a server call")

    // 2. A purchased key unlocks, trimmed of whitespace
    expectEqual(failure(of: await provider.activateLifetime(key: "  \(purchasedKey)\n")), nil, "A purchased key activates")
    expectEqual(await provider.currentStatus(), .unlocked(licenseKey: purchasedKey), "Status shows the activated key")

    // 3. Server reasons are passed through
    for expected in [LicenseActivationError.keyInactive, .activationLimitReached, .wrongProduct, .network("offline")] {
        let failing = makeTestLicenseProvider(StubLicenseVerifier(validKeys: [purchasedKey], failure: expected))
        expectEqual(failure(of: await failing.activateLifetime(key: purchasedKey)), expected, "Activation reports \(expected)")
        expect(!(await failing.currentStatus().isUnlockedLifetime), "Failed activation (\(expected)) does not unlock")
    }

    // 4. The activation survives a relaunch (same storage, new provider)
    let suite = "TidyMacLicenseRelaunch_\(UUID().uuidString)"
    _ = await makeTestLicenseProvider(StubLicenseVerifier(validKeys: [purchasedKey]), suiteName: suite).activateLifetime(key: purchasedKey)
    let relaunched = makeTestLicenseProvider(StubLicenseVerifier(validKeys: [purchasedKey]), suiteName: suite)
    expectEqual(await relaunched.currentStatus(), .unlocked(licenseKey: purchasedKey), "Activation persists across launches")

    // 5. Restore stays unlocked offline, but locks when the key was revoked
    let offline = makeTestLicenseProvider(StubLicenseVerifier(isOffline: true), suiteName: suite)
    expect(await offline.restorePurchases(), "Restore keeps the license when offline")
    expect(await offline.currentStatus().isUnlockedLifetime, "Still unlocked after offline restore")
    let revoked = makeTestLicenseProvider(StubLicenseVerifier(validKeys: [purchasedKey], revokedKeys: [purchasedKey]), suiteName: suite)
    expect(!(await revoked.restorePurchases()), "Restore reports a revoked key")
    expect(!(await revoked.currentStatus().isUnlockedLifetime), "A revoked key locks the app")
    UserDefaults.standard.removePersistentDomain(forName: suite)

    // 6. Keys saved by older builds (any text, never activated) don't count until activated
    let legacySuite = "TidyMacLicenseLegacy_\(UUID().uuidString)"
    UserDefaults(suiteName: legacySuite)!.set("anything", forKey: "TidyMacLifetimeLicenseKey")
    let legacy = makeTestLicenseProvider(StubLicenseVerifier(validKeys: [purchasedKey]), suiteName: legacySuite)
    expect(!(await legacy.currentStatus().isUnlockedLifetime), "An unactivated legacy key does not unlock")
    for _ in 0..<LocalLicenseProvider.maxFreeFolderSorts { await legacy.recordFolderSort() }
    expect(!(await legacy.canSortFolder()), "An unactivated legacy key does not grant unlimited sorting")
    expect(!(await legacy.restorePurchases()), "Restoring a made-up legacy key fails")
    UserDefaults(suiteName: legacySuite)!.set(purchasedKey, forKey: "TidyMacLifetimeLicenseKey")
    let legacyReal = makeTestLicenseProvider(StubLicenseVerifier(validKeys: [purchasedKey]), suiteName: legacySuite)
    expect(await legacyReal.restorePurchases(), "Restoring a real legacy key activates it")
    expect(await legacyReal.currentStatus().isUnlockedLifetime, "A real legacy key unlocks after restore")
    UserDefaults.standard.removePersistentDomain(forName: legacySuite)
}

private func failure(of result: Result<Void, LicenseActivationError>) -> LicenseActivationError? {
    if case .failure(let error) = result { return error }
    return nil
}

private extension LicenseStatus {
    var isUnlockedLifetime: Bool {
        if case .unlocked = self { return true }
        return false
    }
}
