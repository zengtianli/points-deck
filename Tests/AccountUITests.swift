import XCTest
import Foundation

/// Runs the actual installed product. The localhost coordinator observes the
/// isolated production server and retrieves real transport messages in memory.
#if os(iOS)
final class AccountUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "cyou.tianli.pointsdeck")
    var env: [String: String] { ProcessInfo.processInfo.environment }
    var password: String { env["POINTS_QA_ACCOUNT_PASSWORD"]! }
    var changedPassword: String { password + " changed" }
    var recoveredPassword: String { password + " recovered" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-api_base", env["POINTS_QA_BASE"]!]
        app.launch()
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
    }

    @discardableResult func coordinator(_ action: String) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: env["POINTS_QA_COORDINATOR"]! + "/" + action)!)
        request.setValue(env["POINTS_QA_COORDINATOR_TOKEN"]!, forHTTPHeaderField: "X-Points-QA")
        request.timeoutInterval = 100
        let ready = expectation(description: "isolated coordinator " + action)
        var result: Result<[String: Any], Error>?
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { result = .failure(error) }
            else { result = Result { try JSONSerialization.jsonObject(with: data!) as! [String: Any] } }
            ready.fulfill()
        }.resume()
        wait(for: [ready], timeout: 110)
        let value = try result!.get()
        XCTAssertEqual(value["ok"] as? Bool, true, "coordinator rejected " + action)
        return value
    }

    func reveal(_ element: XCUIElement) {
        // SwiftUI Form is a CollectionView. Select the top presented form,
        // rather than scrolling the login page behind a nested sheet.
        let scrolls = app.collectionViews.count > 0 ? app.collectionViews : app.scrollViews
        let area = scrolls.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app
        for _ in 0..<8 where !element.isHittable { area.swipeUp() }
    }
    func dismissKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        // iPad's keyboard hides on the first form-row tap and moves a centered
        // sheet 201.5 pt before touch-up. Finish that transition separately.
        let hide = keyboard.buttons.matching(NSPredicate(format: "label IN %@", ["Hide keyboard", "隐藏键盘"])).firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "native keyboard dismissal control")
        XCTAssertTrue(hide.isHittable, "native keyboard dismissal is hittable")
        hide.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: keyboard)], timeout: 10), .completed, "keyboard dismissed before form action")
    }
    func settled(_ element: XCUIElement) {
        var previous = element.frame
        var stable = 0
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.1)
            let current = element.frame
            stable = current == previous ? stable + 1 : 0
            if stable >= 3 { return }
            previous = current
        }
        XCTFail("native control did not settle")
    }
    func tap(_ name: String) {
        dismissKeyboard()
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", name))
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 15), "missing button " + name)
        var button = buttons.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? buttons.element(boundBy: buttons.count - 1)
        XCTAssertTrue(button.waitForExistence(timeout: 15), "missing button " + name)
        reveal(button)
        button = buttons.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? button
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)], timeout: 20), .completed, "button ready " + name)
        XCTAssertTrue(button.isHittable, "foreground button hittable " + name)
        settled(button)
        print("ACCOUNT-TAP: " + name + " frame=" + String(describing: button.frame))
        button.tap()
    }
    func fill(_ name: String, _ value: String, secure: Bool = false) {
        let fields = (secure ? app.secureTextFields : app.textFields).matching(identifier: name)
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 15), "missing field " + name)
        let field = fields.element(boundBy: fields.count - 1)
        XCTAssertTrue(field.waitForExistence(timeout: 15), "missing field " + name)
        reveal(field); field.tap()
        if let previous = field.value as? String, previous != name {
            // A tap can place the caret inside existing (also masked) text.
            // Native Select All avoids leaving the suffix behind.
            field.typeKey("a", modifierFlags: .command)
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            let cleared = field.value as? String ?? ""
            XCTAssertTrue(cleared.isEmpty || cleared == name, "native old input cleared " + name)
        }
        field.typeText(value)
        for _ in 0..<100 {
            let actual = field.value as? String ?? ""
            if secure ? actual.count == value.count : actual == value { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let actual = field.value as? String ?? ""
        XCTAssertTrue(secure ? actual.count == value.count : actual == value, "native field accepted complete input " + name)
    }
    func waitText(_ fragment: String) {
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch.waitForExistence(timeout: 20), "missing result " + fragment)
    }
    func mark(_ step: String) throws {
        _ = try coordinator("mark/" + step)
        print("ACCOUNT-NATIVE: " + step)
    }
    func login(_ user: String, _ pw: String) {
        tap("密码登录"); fill("手机号、邮箱或原用户名", user)
        fill("登录密码", pw, secure: true); tap("进入账本")
        XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
    }
    func logout() {
        tap("账户"); tap("退出登录"); tap("退出登录")
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
    }
    func verifyEmail(wrongFirst: Bool = false) throws {
        tap("发送验证码")
        XCTAssertTrue(app.textFields["6 位验证码"].firstMatch.waitForExistence(timeout: 30), "native email send receipt")
        let received = try coordinator("otp/email")
        if wrongFirst {
            let wrong = received["code"] as? String == "000000" ? "111111" : "000000"
            fill("6 位验证码", wrong); tap("验证邮箱"); waitText("验证码不正确")
        }
        fill("6 位验证码", received["code"] as! String); tap("验证邮箱")
        waitText("验证完成")
    }
    func verifyPhone(wrongFirst: Bool = false) throws {
        _ = try coordinator("sms-ready")
        tap("获取短信验证码")
        XCTAssertTrue(app.textFields["6 位短信验证码"].firstMatch.waitForExistence(timeout: 30), "native SMS send receipt")
        let received = try coordinator("otp/phone")
        if wrongFirst {
            let wrong = received["code"] as? String == "000000" ? "111111" : "000000"
            fill("6 位短信验证码", wrong); tap("验证手机号"); waitText("验证码不正确")
        }
        fill("6 位短信验证码", received["code"] as! String); tap("验证手机号")
        waitText("手机验证完成")
    }
    func consent() {
        let choices = app.switches.matching(identifier: "我已阅读并同意用户协议与隐私政策")
        let agreed = choices.element(boundBy: choices.count - 1)
        XCTAssertTrue(agreed.waitForExistence(timeout: 10)); reveal(agreed); agreed.tap()
    }
    func delete(_ pw: String) {
        tap("账户"); tap("注销账号")
        fill("当前登录密码", pw, secure: true); tap("确认注销")
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
    }

    func testAccountPasswordLogin() throws {
        let user = env["POINTS_QA_USER"]!
        tap("密码登录"); fill("手机号、邮箱或原用户名", user)
        fill("登录密码", "known-wrong-synthetic-password", secure: true)
        tap("进入账本"); waitText("用户名或密码不对")
        XCTAssertTrue(app.buttons["没有账号？注册账号"].exists)
        XCTAssertFalse(app.buttons["账户"].exists)
        XCTAssertEqual(app.textFields["手机号、邮箱或原用户名"].value as? String, user)
        fill("登录密码", env["POINTS_QA_PASSWORD"]!, secure: true)
        tap("进入账本")
        XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
        try mark("native-password-login")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
        try mark("native-session-restore")
        logout(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
        try mark("native-logout-reopen")
    }

    func testAccountEmailLifecycle() throws {
        try emailLifecycle(readPolicies: true)
    }
    // Separate remaining-flow evidence. A pass here does not clear the failed
    // policy navigation part of testAccountEmailLifecycle or the account gate.
    func testAccountEmailTransport() throws {
        try emailLifecycle(readPolicies: false)
    }
    func emailLifecycle(readPolicies: Bool) throws {
        tap("没有账号？注册账号"); tap("其他地区／使用邮箱注册")
        if readPolicies {
            tap("阅读用户协议"); waitText("成长小金库用户协议")
            closePolicy("用户协议")
            tap("阅读隐私政策"); waitText("成长小金库隐私政策")
            closePolicy("隐私政策")
        }
        fill("邮箱", env["POINTS_QA_EMAIL"]!)
        try verifyEmail(wrongFirst: true)
        fill("密码（15–128 字符）", password, secure: true)
        fill("确认密码", password, secure: true); fill("昵称（可选）", "原生账号验收")
        consent(); tap("注册并登录")
        XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
        try mark("email-registration")
        // Book one actual fixed rule supplied by the production configuration.
        tap("加分"); tap(env["POINTS_QA_EARN_LABEL"]!)
        try mark("business-use")
        tap("账户"); tap("账号安全")
        fill("当前登录密码", password, secure: true)
        fill("可收信的新邮箱", env["POINTS_QA_EMAIL_NEW"]!)
        try verifyEmail(); try verifyEmail()
        tap("保存邮箱"); waitText("邮箱已验证并保存")
        try mark("email-change")
        tap("修改登录密码")
        fill("当前密码", "known-wrong-synthetic-password", secure: true)
        fill("新密码", changedPassword, secure: true)
        fill("确认新密码", changedPassword, secure: true)
        tap("保存新密码"); waitText("旧密码不对")
        XCTAssertTrue(app.secureTextFields["当前密码"].exists)
        fill("当前密码", password, secure: true); tap("保存新密码")
        waitText("密码已修改"); try mark("password-change")
        tap("关闭"); tap("关闭"); logout(); try mark("logout")
        tap("忘记密码"); tap("邮箱")
        fill("已验证的绑定邮箱", env["POINTS_QA_EMAIL_NEW"]!)
        try verifyEmail()
        fill("新密码（15–128 字符）", recoveredPassword, secure: true)
        fill("确认新密码", recoveredPassword, secure: true)
        tap("重置密码"); waitText("密码已重置"); tap("返回登录")
        login(env["POINTS_QA_EMAIL_NEW"]!, recoveredPassword)
        try mark("email-recovery-and-data")
        delete(recoveredPassword); try mark("email-account-deletion")
    }

    func closePolicy(_ title: String) {
        let navigation = app.navigationBars[title].firstMatch
        let close = navigation.buttons["关闭"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(close.isHittable, "visible policy close " + title)
        settled(close); close.tap()
        // Without this, the next policy lookup can select the registration
        // form behind the still-present policy sheet and tap {-1,-1}.
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: navigation)], timeout: 10), .completed, "policy actually dismissed " + title)
    }

    func registerPhone() throws {
        tap("没有账号？注册账号"); fill("+86 手机号", env["POINTS_QA_PHONE"]!)
        try verifyPhone(wrongFirst: true); consent(); tap("注册并登录")
        XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
        try mark("phone-registration")
    }
    func testAccountPhoneLifecycle() throws {
        try registerPhone()
        tap("账户"); tap("账号安全"); tap("设置登录密码")
        try verifyPhone()
        fill("新密码（15–128字符）", password, secure: true)
        fill("确认密码", password, secure: true); tap("设置登录密码")
        waitText("修改登录密码"); try mark("phone-password-set")
        tap("关闭"); logout()
        fill("+86 家长手机号", env["POINTS_QA_PHONE"]!); try verifyPhone()
        tap("进入账本"); XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
        try mark("phone-login"); logout()
        tap("忘记密码"); fill("已验证的 +86 绑定手机号", env["POINTS_QA_PHONE"]!)
        try verifyPhone()
        fill("新密码（15–128 字符）", recoveredPassword, secure: true)
        fill("确认新密码", recoveredPassword, secure: true)
        tap("重置密码"); waitText("密码已重置"); tap("返回登录")
        login(env["POINTS_QA_PHONE"]!, recoveredPassword)
        try mark("phone-recovery-and-data"); delete(recoveredPassword)
        try mark("phone-account-deletion")
    }
    func testAccountPhoneBinding() throws {
        login(env["POINTS_QA_USER"]!, env["POINTS_QA_PASSWORD"]!)
        tap("账户"); tap("账号安全"); tap("绑定／更换手机号")
        fill("当前登录密码", env["POINTS_QA_PASSWORD"]!, secure: true)
        fill("+86 家长手机号", env["POINTS_QA_PHONE"]!)
        try verifyPhone(); tap("确认保存手机号")
        waitText("确认原手机号"); try mark("phone-binding-preserved")
        try mark("phone-change-missing-second-number")
    }
    func testAccountPasswordlessDeletion() throws {
        try registerPhone(); tap("账户"); tap("注销账号")
        try verifyPhone(); tap("确认注销")
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
        try mark("passwordless-account-deletion")
    }
}
#endif
