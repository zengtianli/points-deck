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

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { print("ACCOUNT-TREE-BEGIN\n" + app.debugDescription + "\nACCOUNT-TREE-END") }
    }

    @discardableResult func coordinator(_ action: String) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: env["POINTS_QA_COORDINATOR"]! + "/" + action)!)
        request.setValue(env["POINTS_QA_COORDINATOR_TOKEN"]!, forHTTPHeaderField: "X-Points-QA")
        request.timeoutInterval = 240
        let ready = expectation(description: "isolated coordinator " + action)
        var result: Result<[String: Any], Error>?
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { result = .failure(error) }
            else { result = Result { try JSONSerialization.jsonObject(with: data!) as! [String: Any] } }
            ready.fulfill()
        }.resume()
        wait(for: [ready], timeout: 250)
        let value = try result!.get()
        XCTAssertEqual(value["ok"] as? Bool, true, "coordinator rejected " + action)
        return value
    }

    var keyboardVisible: Bool {
        let keyboard = app.keyboards.firstMatch
        // XCTest typing is a hardware keyboard to iOS: the software keys
        // minimise but AX can keep the object. Only hittable keys are on screen.
        return keyboard.exists && keyboard.keys.allElementsBoundByIndex.contains(where: { $0.isHittable })
    }
    func topScroll() -> XCUIElement {
        let scrolls = app.collectionViews.count > 0 ? app.collectionViews : app.scrollViews
        let all = scrolls.allElementsBoundByIndex
        return all.last(where: { $0.isHittable }) ?? all.last ?? app
    }
    /// The part of the front page a finger can reach. The minimised keyboard
    /// window makes XCTest report rows under it as not hittable although they
    /// are plainly on screen, so visibility is decided from geometry.
    func reach(_ area: XCUIElement) -> CGRect {
        var visible = area.frame.insetBy(dx: 0, dy: 10)
        let screen = app.windows.firstMatch.frame
        visible = visible.intersection(CGRect(x: 0, y: screen.minY + 60, width: screen.width, height: screen.height - 60 - 34))
        if keyboardVisible {
            // The autofill/prediction bar, when the keyboard has one, sits above the keys.
            let bar = app.otherElements["SystemInputAssistantView"].firstMatch
            var top = app.keyboards.firstMatch.frame.minY
            if bar.exists && !bar.frame.isEmpty { top = min(top, bar.frame.minY) }
            visible.size.height = max(0, min(visible.maxY, top - 6) - visible.minY)
        }
        return visible
    }
    func shown(_ element: XCUIElement, in area: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && reach(area).contains(CGPoint(x: frame.midX, y: frame.midY))
    }
    /// One finger drag of the front page. It starts on a spot that is not a
    /// text field: a drag that begins on the focused field moves its caret
    /// instead of the page (seen with the phone pad up).
    func scroll(_ area: XCUIElement, up: Bool, distance: CGFloat = 260) {
        let visible = reach(area)
        let fields = (area.descendants(matching: .textField).allElementsBoundByIndex
            + area.descendants(matching: .secureTextField).allElementsBoundByIndex).map { $0.frame.insetBy(dx: 0, dy: -14) }
        let fractions: [CGFloat] = up ? [0.75, 0.6, 0.45, 0.3, 0.88] : [0.25, 0.4, 0.55, 0.7, 0.12]
        var y = visible.minY + visible.height * fractions[0]
        for f in fractions {
            let candidate = visible.minY + visible.height * f
            if !fields.contains(where: { $0.minY <= candidate && candidate <= $0.maxY }) { y = candidate; break }
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: visible.midX, dy: y))
        let end = origin.withOffset(CGVector(dx: visible.midX, dy: up ? max(visible.minY - 40, y - distance) : y + distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 0.5)
    }
    func reveal(_ element: XCUIElement) {
        let area = topScroll()
        for _ in 0..<8 {
            if shown(element, in: area) { return }
            let before = element.exists ? element.frame : .zero
            // A field above the viewport is recycled out of the AX tree;
            // repeatedly swiping up can never reveal it.
            scroll(area, up: element.exists && !before.isEmpty && before.midY >= reach(area).midY)
            // Nothing moved: the page is at its end. More swipes only risk
            // being taken as a tap on whatever row they start on.
            if element.exists && element.frame == before { return }
        }
    }
    /// Lazy lists keep rows below the fold out of the AX tree. Look for the
    /// control the way a person does: scroll down the page, then back up.
    func hunt(_ query: XCUIElementQuery) {
        if query.firstMatch.waitForExistence(timeout: 4) { return }
        let area = topScroll()
        for _ in 0..<6 { scroll(area, up: true); if query.firstMatch.exists { return } }
        for _ in 0..<8 { scroll(area, up: false); if query.firstMatch.exists { return } }
    }
    func dismissKeyboard() {
        guard keyboardVisible else { return }
        let keyboard = app.keyboards.firstMatch
        let hide = keyboard.buttons.matching(NSPredicate(format: "label IN %@", ["Hide keyboard", "隐藏键盘"])).firstMatch
        let done = keyboard.buttons.matching(NSPredicate(format: "identifier IN %@", ["Return", "Done", "Go", "Next:"])).firstMatch
        if hide.exists && hide.isHittable {
            hide.tap()
        } else if done.exists && done.isHittable {
            done.tap()   // what a person does on iPhone: return ends editing
        } else {
            // Number and phone pads have no return key. A Form dismisses the
            // keyboard on scroll; a plain ScrollView keeps it, and reveal()
            // then scrolls the target above the keyboard instead.
            scroll(topScroll(), up: true, distance: 120)
        }
        for _ in 0..<20 where keyboardVisible { Thread.sleep(forTimeInterval: 0.1) }
        // The form keeps sliding back for a moment after the keys are gone;
        // a tap aimed during that slide lands on a neighbouring row.
        Thread.sleep(forTimeInterval: 0.7)
    }
    func settled(_ element: XCUIElement) {
        var previous = element.frame
        var stable = 0
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.1)
            let current = element.frame
            stable = current == previous ? stable + 1 : 0
            if stable >= 5 { return }
            previous = current
        }
        XCTFail("native control did not settle")
    }
    func press(_ element: XCUIElement) {
        // A touch at the control's centre, like a finger. element.tap() would
        // first try to scroll a "not hittable" row and move the page.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    func tap(_ name: String, occurrence: Int? = nil) {
        dismissKeyboard()
        if ["账本", "走势", "加分", "兑换", "账户"].contains(name) {
            let tabs = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", name))
            if let tab = tabs.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                // The floating tab bar re-lays out while a page transition or
                // score animation is running; confirm the selection landed.
                for _ in 0..<4 {
                    settled(tab); tab.tap()
                    if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)], timeout: 3) == .completed {
                        print("ACCOUNT-TAB: " + name); return
                    }
                }
                XCTFail("tab not selected " + name); return
            }
        }
        // Sheets leave the page behind them in the AX tree (the login page has
        // its own, disabled, verification button). Prefer the front container;
        // navigation bars and confirmation dialogs live outside it.
        let label = NSPredicate(format: "label == %@", name)
        let area = topScroll()
        let front = area.descendants(matching: .button).matching(label)
        let anywhere = app.buttons.matching(label)
        var inFront = true
        if !front.firstMatch.waitForExistence(timeout: 2) {
            if anywhere.allElementsBoundByIndex.contains(where: { $0.isHittable }) { inFront = false }
            else { hunt(front); inFront = front.firstMatch.exists }
        }
        let buttons = inFront ? front : anywhere
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 15), "missing button " + name)
        func pick() -> XCUIElement {
            if let occurrence { return buttons.element(boundBy: occurrence) }
            let all = buttons.allElementsBoundByIndex
            return (inFront ? all.last(where: { shown($0, in: area) }) : all.last(where: { $0.isHittable })) ?? all[all.count - 1]
        }
        var button = pick()
        XCTAssertTrue(button.waitForExistence(timeout: 15), "missing button " + name)
        if inFront { reveal(button); button = pick() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)], timeout: 20), .completed, "button ready " + name)
        settled(button)
        XCTAssertTrue(inFront ? shown(button, in: area) : button.isHittable, "foreground button on screen " + name)
        print("ACCOUNT-TAP: " + name + " frame=" + String(describing: button.frame))
        press(button)
    }
    /// The confirmation dialog repeats the row's own label; press the copy
    /// that is not a row of the page.
    func confirm(_ name: String) {
        let label = NSPredicate(format: "label == %@", name)
        let rows = topScroll().descendants(matching: .button).matching(label)
        var target: XCUIElement?
        for _ in 0..<50 where target == nil {
            let rowFrames = rows.allElementsBoundByIndex.map { $0.frame }
            target = app.buttons.matching(label).allElementsBoundByIndex.first(where: { $0.isHittable && !rowFrames.contains($0.frame) })
            if target == nil { Thread.sleep(forTimeInterval: 0.2) }
        }
        guard let target else { XCTFail("missing confirmation " + name); return }
        settled(target)
        print("ACCOUNT-CONFIRM: " + name + " frame=" + String(describing: target.frame))
        target.tap()
    }
    func fill(_ name: String, _ value: String, secure: Bool = false) {
        dismissKeyboard()
        let kind: XCUIElement.ElementType = secure ? .secureTextField : .textField
        var fields = topScroll().descendants(matching: kind).matching(identifier: name)
        hunt(fields)
        if !fields.firstMatch.exists { fields = (secure ? app.secureTextFields : app.textFields).matching(identifier: name) }
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 15), "missing field " + name)
        let field = fields.element(boundBy: fields.count - 1)
        XCTAssertTrue(field.waitForExistence(timeout: 15), "missing field " + name)
        reveal(field); settled(field); press(field)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)], timeout: 8), .completed, "native field focused " + name)
        if let previous = field.value as? String, previous != name, !previous.isEmpty {
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
        Thread.sleep(forTimeInterval: 0.3)
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
        tap("账户"); tap("退出登录"); confirm("退出登录")
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
    }
    func verifyEmail(wrongFirst: Bool = false) throws {
        tap("发送验证码", occurrence: 0)
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
        tap("获取短信验证码", occurrence: 0)
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
        dismissKeyboard()
        // Email registration sits on top of the phone registration sheet, whose
        // own consent row stays in the AX tree; the front one is below the fold.
        let choices = topScroll().descendants(matching: .switch).matching(identifier: "我已阅读并同意用户协议与隐私政策")
        hunt(choices)
        let agreed = choices.firstMatch
        XCTAssertTrue(agreed.waitForExistence(timeout: 10)); reveal(agreed); settled(agreed)
        // AX gives the whole Form row a switch role; touch the actual control.
        let toggle = agreed.switches.firstMatch
        if toggle.exists { settled(toggle); press(toggle) }
        else { agreed.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1'"), object: agreed)], timeout: 10), .completed, "native consent switched on")
    }
    func delete(_ pw: String) {
        tap("账户"); tap("注销账号")
        fill("当前登录密码", pw, secure: true); tap("确认注销")
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
    }

    func testAccountPasswordLogin() throws {
        if env["POINTS_QA_MODE"] == "PeerStart" {
            login(env["POINTS_QA_USER"]!, env["POINTS_QA_PASSWORD"]!)
            print("ACCOUNT-NATIVE: native-peer-signed-in")
            return
        }
        if env["POINTS_QA_MODE"] == "PeerCheck" {
            XCTAssertFalse(app.buttons["账户"].exists)
            print("ACCOUNT-NATIVE: native-peer-session-invalidated")
            return
        }
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
        if env["POINTS_QA_MODE"] == "EmailBinding" {
            login(env["POINTS_QA_USER"]!, env["POINTS_QA_PASSWORD"]!)
            tap("账户"); tap("账号安全")
            fill("当前登录密码", env["POINTS_QA_PASSWORD"]!, secure: true)
            fill("可收信的新邮箱", env["POINTS_QA_EMAIL"]!)
            try verifyEmail(wrongFirst: true); try mark("email-wrong-code-then-correct")
            tap("保存邮箱"); waitText("邮箱已验证并保存")
            try mark("email-binding-preserved")
            tap("关闭"); logout()
            login(env["POINTS_QA_EMAIL"]!, env["POINTS_QA_PASSWORD"]!)
            try mark("email-binding-login")
            return
        }
        try emailLifecycle(readPolicies: false)
    }
    func emailLifecycle(readPolicies: Bool) throws {
        tap("没有账号？注册账号"); tap("其他地区／使用邮箱注册")
        if readPolicies {
            tap("阅读用户协议"); waitText("成长小金库用户协议")
            closePolicy("用户协议")
            tap("阅读隐私政策"); waitText("成长小金库隐私政策")
            closePolicy("隐私政策")
            try mark("native-policies-read-and-closed")
        }
        fill("邮箱", env["POINTS_QA_EMAIL"]!)
        // Keep the recorded wrong-code attempt separate from this positive
        // lifecycle. This pass cannot satisfy abuse_protection.
        try verifyEmail()
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

    func registerPhone(wrongFirst: Bool = true) throws {
        tap("没有账号？注册账号"); fill("+86 手机号", env["POINTS_QA_PHONE"]!)
        try verifyPhone(wrongFirst: wrongFirst)
        if wrongFirst { try mark("phone-wrong-code-then-correct") }
        consent(); tap("注册并登录")
        XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
        try mark("phone-registration")
    }
    func testAccountPhoneLifecycle() throws {
        if env["POINTS_QA_MODE"] == "PhoneResume" {
            fill("+86 家长手机号", env["POINTS_QA_PHONE"]!); try verifyPhone()
            tap("进入账本"); XCTAssertTrue(app.buttons["账户"].waitForExistence(timeout: 20))
            try mark("phone-resume-login")
        } else { try registerPhone(wrongFirst: true) }
        tap("加分"); tap(env["POINTS_QA_EARN_LABEL"]!)
        try mark("business-use")
        tap("账户"); tap("账号安全"); tap("设置登录密码")
        try verifyPhone()
        fill("新密码（15–128字符）", password, secure: true)
        fill("确认密码", password, secure: true); tap("设置登录密码")
        XCTAssertTrue(app.buttons["修改登录密码"].waitForExistence(timeout: 20))
        try mark("phone-password-set")
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
        try mark("phone-binding-peer-start")
        tap("账户"); tap("账号安全"); tap("绑定／更换手机号")
        fill("当前登录密码", env["POINTS_QA_PASSWORD"]!, secure: true)
        fill("+86 家长手机号", env["POINTS_QA_PHONE"]!)
        try verifyPhone(); tap("确认保存手机号")
        waitText("确认原手机号"); try mark("phone-binding-preserved")
        if env["POINTS_QA_MODE"] == "BindOnly" { return }
        try mark("phone-change-peer-start")
        fill("当前登录密码", env["POINTS_QA_PASSWORD"]!, secure: true)
        fill("+86 家长手机号", env["POINTS_QA_PHONE_NEW"]!)
        try verifyPhone(); try verifyPhone()
        tap("确认保存手机号"); waitText("更换手机号成功")
        try mark("phone-change-preserved")
    }
    func testAccountPasswordlessDeletion() throws {
        // The wrong-SMS-code attempt is kept out of this flow: against the real
        // provider the backend answers it with 503 "核验服务暂不可用" instead of
        // "验证码不正确" (recorded 2026-10-09 as a backend defect, not papered over here).
        try registerPhone(wrongFirst: false); tap("账户"); tap("注销账号")
        try verifyPhone(); tap("确认注销")
        XCTAssertTrue(app.buttons["没有账号？注册账号"].waitForExistence(timeout: 20))
        try mark("passwordless-account-deletion")
    }
}
#endif
