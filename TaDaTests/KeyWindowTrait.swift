// `.keyWindow`: suites whose tests need the key window take turns, since Swift Testing runs suites in parallel.
import Testing

nonisolated struct KeyWindowTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        guard testCase != nil else { return try await function() }
        await KeyWindowTurns.shared.take()
        do {
            try await function()
        } catch {
            await KeyWindowTurns.shared.give()
            throw error
        }
        await KeyWindowTurns.shared.give()
    }
}

extension Trait where Self == KeyWindowTrait {
    static var keyWindow: Self { KeyWindowTrait() }
}

private actor KeyWindowTurns {
    static let shared = KeyWindowTurns()
    private var isTaken = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func take() async {
        guard isTaken else {
            isTaken = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func give() {
        if waiting.isEmpty { isTaken = false } else { waiting.removeFirst().resume() }
    }
}
