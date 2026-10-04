import AppKit
import XCTest

/// Hosted by the actual source-verified .lane Mac App, not a substitute window.
final class MacHostedTests: XCTestCase {
    @MainActor func testWindowMenuAndCloseKey() async throws {
        for _ in 0..<100 where NSApp.windows.first(where: { $0.contentView != nil && $0.styleMask.contains(.titled) }) == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        let window = try XCTUnwrap(NSApp.windows.first { $0.contentView != nil && $0.styleMask.contains(.titled) })
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertLessThan(window.frame.origin.x, -1000)
        XCTAssertGreaterThanOrEqual(window.minSize.width, 760)
        let menu = try XCTUnwrap(NSApp.mainMenu)
        func items(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
        }
        let commands = items(menu)
        for item in commands where !item.keyEquivalent.isEmpty {
            print("POINTS_MAC_KEY \(item.keyEquivalent) \(item.action.map(NSStringFromSelector) ?? "nil")")
        }
        XCTAssertTrue(commands.contains { $0.action == NSSelectorFromString("terminate:") && $0.keyEquivalent == "q" })
        XCTAssertTrue(commands.contains { $0.keyEquivalent == "w" })
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        window.makeMain()
        window.makeKey()
        try await Task.sleep(for: .milliseconds(250))
        let close = try XCTUnwrap(commands.first { $0.keyEquivalent == "w" &&
            $0.action == NSSelectorFromString("performClose:") && $0.keyEquivalentModifierMask == .command })
        // The host is deliberately inactive. Execute the real Cmd-W selector
        // on its own window without dispatching a key to the user's active App.
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(close.action), to: window, from: close))
        await fulfillment(of: [closed], timeout: 10)
    }
}
