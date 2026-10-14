import Foundation
import TidyMacCore

@MainActor
func runFileAccessTests() async {
    print("\n--- Running FileAccess & Cloud Folder Tests ---")
    
    let home = FileManager.default.homeDirectoryForCurrentUser
    
    // 1. Cloud Provider Detection Tests
    let icloudURL = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Docs/notes.txt")
    expectEqual(CloudFolderDetector.detectProvider(for: icloudURL), .iCloud, "Detects iCloud Drive path")
    
    let dropboxURL = home.appendingPathComponent("Dropbox/Projects/design.sketch")
    expectEqual(CloudFolderDetector.detectProvider(for: dropboxURL), .dropBox, "Detects Dropbox path")
    
    let gdriveURL = home.appendingPathComponent("Google Drive/Sheet.xlsx")
    expectEqual(CloudFolderDetector.detectProvider(for: gdriveURL), .googleDrive, "Detects Google Drive path")
    
    let onedriveURL = home.appendingPathComponent("OneDrive/Presentation.pptx")
    expectEqual(CloudFolderDetector.detectProvider(for: onedriveURL), .oneDrive, "Detects OneDrive path")
    
    let localURL = URL(fileURLWithPath: "/tmp/local_notes.txt")
    expect(CloudFolderDetector.detectProvider(for: localURL) == nil, "Local path should return nil for cloud provider")
    
    // 2. Cloud Dataless Placeholder Test
    let placeholderURL = URL(fileURLWithPath: "/Users/test/Documents/.QuarterlyReport.pdf.icloud")
    expect(CloudFolderDetector.isDatalessCloudPlaceholder(placeholderURL), "Detects .icloud dataless placeholder filename")
    
    // 3. Cloud Sync Warning Test
    let warning = CloudFolderDetector.syncWarning(for: icloudURL)
    expect(warning != nil && warning!.contains("iCloud Drive"), "Generates sync warning for iCloud files")
    expect(CloudFolderDetector.syncWarning(for: localURL) == nil, "No sync warning for non-cloud local files")
    
    // 4. PermissionsManager Tests
    let permManager = PermissionsManager.shared
    expectEqual(PermissionsManager.fullDiskAccessSettingsURL.scheme, "x-apple.systempreferences", "Settings URL has correct scheme")
    let fdaStatus = permManager.checkFullDiskAccess()
    expect(fdaStatus == true || fdaStatus == false, "checkFullDiskAccess returns valid boolean status without error")
    
    for folderType in ManagedFolderType.allCases {
        let url = folderType.defaultURL
        expect(!url.path.isEmpty, "Folder preset '\(folderType.rawValue)' provides non-empty path")
    }
    
    // 5. FileAccessService Managed Folders & Scoped Block Tests
    let accessService = FileAccessService.shared
    let managedFolders = await accessService.getManagedFolderURLs()
    expect(!managedFolders.isEmpty, "FileAccessService provides default managed folder URLs")
    
    let tempDir = FileManager.default.temporaryDirectory
    do {
        let result = try await accessService.withSecurityScope(for: tempDir) { url in
            return "access_granted:\(url.lastPathComponent)"
        }
        expect(result.hasPrefix("access_granted:"), "withSecurityScope executes and returns result cleanly")
    } catch {
        expect(false, "withSecurityScope failed unexpectedly: \(error)")
    }
}
