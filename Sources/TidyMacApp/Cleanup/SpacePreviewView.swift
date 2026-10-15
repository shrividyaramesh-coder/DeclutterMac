import SwiftUI
import TidyMacCore

public struct SpacePreviewView: View {
    public let currentFreeBytes: Int64
    public let selectedCleanupBytes: Int64

    public init(currentFreeBytes: Int64, selectedCleanupBytes: Int64) {
        self.currentFreeBytes = currentFreeBytes
        self.selectedCleanupBytes = selectedCleanupBytes
    }

    public var projectedFreeBytes: Int64 {
        currentFreeBytes + selectedCleanupBytes
    }

    public var body: some View {
        HStack(spacing: 24) {
            statItem(
                label: localized("preview.current_free"),
                bytes: currentFreeBytes,
                systemImage: "internaldrive",
                color: .secondary
            )

            Image(systemName: "plus")
                .font(.headline)
                .foregroundStyle(.secondary)

            statItem(
                label: localized("preview.selected_size"),
                bytes: selectedCleanupBytes,
                systemImage: "trash.circle.fill",
                color: .orange
            )

            Image(systemName: "arrow.right")
                .font(.headline)
                .foregroundStyle(.secondary)

            statItem(
                label: localized("preview.projected_free"),
                bytes: projectedFreeBytes,
                systemImage: "arrow.triangle.2.circlepath",
                color: .green
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func statItem(label: String, bytes: Int64, systemImage: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.headline)
                .bold()
                .foregroundStyle(color == .secondary ? .primary : color)
        }
    }
}
