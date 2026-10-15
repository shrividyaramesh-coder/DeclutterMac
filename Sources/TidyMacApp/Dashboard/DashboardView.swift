import SwiftUI
import TidyMacCore

public struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboardingSheet: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("nav.overview"))
                            .font(.largeTitle)
                            .bold()
                        Text(localized("app.tagline"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        appState.selectedNavigation = .cleanup
                    }) {
                        Label(localized("action.scan"), systemImage: "magnifyingglass")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // Permissions Warning Banner if Full Disk Access is not granted
                if !appState.hasFullDiskAccess {
                    permissionBanner
                }

                // Storage Bar
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("dashboard.disk_usage"))
                        .font(.headline)
                    DiskUsageBar(
                        totalBytes: appState.storageSummary.totalDiskBytes,
                        usedBytes: appState.storageSummary.usedDiskBytes,
                        reclaimableBytes: appState.storageSummary.reclaimableBytes,
                        freeBytes: appState.storageSummary.freeDiskBytes
                    )
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // KPI Metric Cards
                HStack(spacing: 16) {
                    metricCard(
                        title: localized("dashboard.reclaimable_now"),
                        value: appState.storageSummary.formattedReclaimable,
                        systemImage: "arrow.down.to.line.compact",
                        color: .orange
                    )
                    metricCard(
                        title: localized("dashboard.lifetime_reclaimed"),
                        value: appState.storageSummary.formattedLifetimeReclaimed,
                        systemImage: "checkmark.seal.fill",
                        color: .green
                    )
                }

                // Category Breakdown Cards
                Text("Storage Breakdown")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 16) {
                    ForEach(ScanCategory.allCases) { category in
                        categoryCard(category: category)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            appState.hasFullDiskAccess = PermissionsManager.shared.checkFullDiskAccess()
        }
        .sheet(isPresented: $showOnboardingSheet) {
            OnboardingView()
                .environmentObject(appState)
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("permission.fda_title"))
                    .font(.subheadline)
                    .bold()
                Text(localized("permission.fda_desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Grant Access") {
                PermissionsManager.shared.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Button("Learn More") {
                showOnboardingSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func metricCard(title: String, value: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2)
                    .bold()
            }
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func categoryCard(category: ScanCategory) -> some View {
        let bytes = appState.storageSummary.categoryBreakdown[category] ?? 0
        return Button(action: {
            appState.selectedNavigation = .cleanup
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: category.systemImage)
                        .font(.title3)
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(category.defaultRisk.title)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(category.defaultRisk == .safe ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .foregroundStyle(category.defaultRisk == .safe ? Color.green : Color.orange)
                        .clipShape(Capsule())
                }
                Text(category.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.headline)
                    .bold()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
