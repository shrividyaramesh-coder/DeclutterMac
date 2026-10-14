import Foundation
import TidyMacCore

public struct TestFailure: Sendable, CustomStringConvertible {
    public let message: String
    public let file: String
    public let line: Int

    public var description: String {
        "❌ Assertion Failed: \(message) at \(file):\(line)"
    }
}

@MainActor
public final class TestHarness {
    public static let shared = TestHarness()
    public var totalTestsRun = 0
    public var totalTestFailures: [TestFailure] = []

    private init() {}

    public func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        totalTestsRun += 1
        if !condition {
            let failure = TestFailure(message: message, file: file, line: line)
            totalTestFailures.append(failure)
            print("  ❌ FAIL: \(message) (\(file):\(line))")
        } else {
            print("  ✅ PASS: \(message)")
        }
    }

    public func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
        expect(a == b, "\(message) [Expected \(b), got \(a)]", file: file, line: line)
    }

    public func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
        expect(a != b, "\(message) [Did not expect \(a)]", file: file, line: line)
    }
}

@MainActor
public func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    TestHarness.shared.expect(condition, message, file: file, line: line)
}

@MainActor
public func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    TestHarness.shared.expectEqual(a, b, message, file: file, line: line)
}

@MainActor
public func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    TestHarness.shared.expectNotEqual(a, b, message, file: file, line: line)
}
