import XCTest

/// A separate UI runner drives the installed, source-verified production App.
/// It neither links replacement product code nor substitutes Store/API/storage.
final class PlatformUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "cyou.tianli.pointsdeck")
    var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-api_base", env["POINTS_QA_BASE"]!, "-dev_user", env["POINTS_QA_USER"]!,
                               "-dev_pw", env["POINTS_QA_PASSWORD"]!, "-tab", "2"]
        app.launch()
        XCTAssertTrue(app.staticTexts["当前积分 1133"].waitForExistence(timeout: 20), app.debugDescription)
    }

    func tap(_ label: String) {
        let buttons = app.buttons.matching(identifier: label)
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 10), "missing button: " + label)
        (buttons.allElementsBoundByIndex.first { $0.isHittable } ?? buttons.firstMatch).tap()
    }

    func fill(_ placeholder: String, _ value: String) {
        let field = app.textFields[placeholder].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "missing field: " + placeholder)
        field.tap()
        if let previous = field.value as? String, previous != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    func picture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCoreEditingAndReopen() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        #endif
        tap("账本"); picture("ledger-real-data")
        tap("走势"); picture("trend-real-data")
        tap("加分")
        tap("新建")
        fill("项目名", "QA-Points-Project")
        fill("正整数分值", "7")
        picture("project-keyboard-input")
        tap("完成")
        tap("保存")
        let saved = app.buttons["保存"].firstMatch
        XCTAssertTrue(NSPredicate(format: "enabled == false").evaluate(with: saved) ||
                      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: saved)], timeout: 10) == .completed)
        tap("关闭")
        tap("兑换")
        tap("新建")
        fill("奖励名", "QA-Points-Reward")
        fill("所需积分", "4")
        picture("reward-keyboard-input")
        tap("完成")
        tap("保存")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: app.buttons["保存"].firstMatch)], timeout: 10), .completed)
        tap("关闭")
        tap("账户")
        XCTAssertTrue(app.buttons["账号安全"].waitForExistence(timeout: 10))
        picture("account-native-entry")
        app.terminate()
        app.launchArguments = ["-api_base", env["POINTS_QA_BASE"]!, "-tab", "4"]
        app.launch()
        XCTAssertTrue(app.buttons["账号安全"].waitForExistence(timeout: 20), "stored-session reopen")
        picture("stored-session-reopen")
        let signout = app.buttons["退出登录"].firstMatch
        for _ in 0..<8 where !signout.isHittable { app.swipeUp() }
        tap("退出登录"); tap("退出登录")
        tap("密码登录")
        fill("手机号、邮箱或原用户名", env["POINTS_QA_USER"]!)
        let password = app.secureTextFields["登录密码"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap(); password.typeText(env["POINTS_QA_PASSWORD"]!)
        tap("进入账本")
        XCTAssertTrue(app.buttons["账号安全"].waitForExistence(timeout: 20), "native password form enters original ledger")
    }

    func testPhoneWatchLogout() throws {
        // Let the real WC delegate activate and deliver the signed-in context.
        // The runner observes the actual Watch home before continuing this test.
        Thread.sleep(forTimeInterval: 90)
        tap("账户")
        let signout = app.buttons["退出登录"].firstMatch
        for _ in 0..<8 where !signout.isHittable { app.swipeUp() }
        tap("退出登录")
        tap("退出登录")
        XCTAssertTrue(app.buttons["进入账本"].waitForExistence(timeout: 15))
        picture("phone-signed-out")
        Thread.sleep(forTimeInterval: 20)
    }
}
