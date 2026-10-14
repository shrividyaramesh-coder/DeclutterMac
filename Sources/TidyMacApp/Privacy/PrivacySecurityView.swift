import SwiftUI
import AppKit
import TidyMacCore

public struct PrivacySecurityView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.shield.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("privacy.title"))
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Tidy Mac is engineered with local-first, privacy-by-design principles.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Core Guarantees Cards
                VStack(spacing: 16) {
                    guaranteeCard(
                        icon: "lock.shield.fill",
                        color: .green,
                        title: "100% Local Scanning & Zero Cloud Uploads",
                        description: "All file scanning, duplicate comparison, and uninstallation logic executes entirely on your Mac. No file lists or scan histories are ever sent to remote servers."
                    )
                    
                    guaranteeCard(
                        icon: "eye.slash.fill",
                        color: .blue,
                        title: "Strict Metadata-Only AI Boundary",
                        description: "When using the AI cleanup planner, only file names, extensions, sizes, and modification dates are processed. File contents, photos, and document text are never opened, buffered, or shared with AI providers."
                    )
                    
                    guaranteeCard(
                        icon: "trash.slash.fill",
                        color: .orange,
                        title: "Trash-Only Deletion — Zero Permanent Erase",
                        description: "Tidy Mac strictly moves items to macOS Trash. Permanent deletion is prohibited by code design. Any cleaned item can be inspected in the Trash and restored with a single click."
                    )
                    
                    guaranteeCard(
                        icon: "shield.lefthalf.filled",
                        color: .purple,
                        title: "Hard-Coded Protected Paths Denylist",
                        description: "System libraries, personal identity keys (~/.ssh, ~/.gnupg), Apple Mail, and Photos libraries are permanently locked against modification or trashing."
                    )
                }
                
                // Full Disk Access Helper
                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("permission.fda_title"))
                        .font(.headline)
                    Text(localized("permission.fda_desc"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        NSWorkspace.shared.open(PermissionsManager.fullDiskAccessSettingsURL)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                            Text(localized("permission.open_settings"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding(28)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func guaranteeCard(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 32)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
