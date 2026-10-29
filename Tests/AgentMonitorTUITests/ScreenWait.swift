import Dispatch
@_spi(Testing) import SwiftTUITestSupport
import Testing

func waitForScreen(
    on fileDescriptor: Int32, screen: inout ANSIVisibleScreen, deadline: DispatchTime,
    condition: (String) -> Bool
) async throws -> String {
    do {
        return try await waitForANSIVisibleScreen(
            on: fileDescriptor, screen: &screen, deadline: deadline, condition: condition)
    } catch let error as RealTerminalJourneyError {
        try Task.checkCancellation()
        // SwiftTUI 0.14.0 checks its deadline before testing the screen it just drained.
        if case .timedOut(let rendered, _) = error, condition(rendered) { return rendered }
        throw error
    }
}

@Test(arguments: [true, false])
func completedScreenWinsDeadlineButMissingContentStillTimesOut(matches: Bool) async throws {
    let terminal = try RealTerminalPTYPair.open(size: .init(width: 40, height: 8), stallBudget: nil)
    defer { terminal.close() }
    var screen = ANSIVisibleScreen(size: .init(width: 40, height: 8))
    screen.feed(Array("Complete".utf8))
    do {
        let rendered = try await waitForScreen(on: terminal.master, screen: &screen, deadline: .now()) {
            $0.contains(matches ? "Complete" : "Missing")
        }
        #expect(matches)
        #expect(rendered.contains("Complete"))
    } catch let error as RealTerminalJourneyError {
        #expect(!matches)
        guard case .timedOut(let rendered, _) = error else {
            Issue.record("Expected a deadline failure, got \(error)")
            return
        }
        #expect(rendered.contains("Complete"))
    }
}
