import Foundation
import CryptoKit

/// Streaming cryptographic hash utilities for high-performance file comparison.
public struct HashUtility: Sendable {
    private static let partialChunkSize = 16 * 1024 // 16 KB

    /// Computes a fast partial hash taking the first 16 KB and last 16 KB of a file.
    public static func computePartialHash(for url: URL, fileSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()

        // Read head
        let headData = handle.readData(ofLength: partialChunkSize)
        hasher.update(data: headData)

        // Read tail if file is larger than 32 KB
        if fileSize > Int64(partialChunkSize * 2) {
            do {
                try handle.seek(toOffset: UInt64(fileSize - Int64(partialChunkSize)))
                let tailData = handle.readData(ofLength: partialChunkSize)
                hasher.update(data: tailData)
            } catch {
                // If seek fails, return hash of head
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes full SHA-256 hash using chunked 64 KB streaming reads to preserve memory.
    public static func computeFullHash(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024 // 64 KB buffer

        while true {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
