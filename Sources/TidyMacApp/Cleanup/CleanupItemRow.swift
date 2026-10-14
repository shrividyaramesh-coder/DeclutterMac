import SwiftUI
import AppKit
import TidyMacCore

public struct CleanupItemRow: View {
    @Binding public var item: FileItem

    public init(item: Binding<FileItem>) {
        self._item = item
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Checkbox: Invariant - strictly disabled if risk is manual
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { item.setSelected($0) }
            ))
            .toggleStyle(.checkbox)
            .disabled(!item.riskLabel.isSelectable)
            .labelsHidden()

            // Category Icon
            Image(systemName: item.category.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            // File Name & Path
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text(item.relativePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Risk Badge
            riskBadge(item.riskLabel)

            // File Size
            Text(item.formattedSize)
                .font(.subheadline)
                .bold()
                .frame(width: 80, alignment: .trailing)

            // Reveal in Finder Button
            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help(localized("action.reveal_in_finder"))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(item.isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func riskBadge(_ risk: RiskLabel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: risk.systemImage)
            Text(risk.title)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeBackground(for: risk))
        .foregroundStyle(badgeColor(for: risk))
        .clipShape(Capsule())
        .help(risk.explanation)
    }

    private func badgeColor(for risk: RiskLabel) -> Color {
        switch risk {
        case .safe: return .green
        case .review: return .orange
        case .manual: return .secondary
        }
    }

    private func badgeBackground(for risk: RiskLabel) -> Color {
        badgeColor(for: risk).opacity(0.15)
    }
}
