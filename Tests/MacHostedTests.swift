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
        XCTAssertTrue(commands.contains { $0.action == NSSelectorFromString("terminate:") && $0.keyEquivalent == "q" })
        XCTAssertTrue(commands.contains { $0.keyEquivalent == "w" })
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        window.makeKey()
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        XCTAssertTrue(menu.performKeyEquivalent(with: key))
        await fulfillment(of: [closed], timeout: 10)
    }
}
