import XCTest

/// Captures the shipped SwiftUI views through normal UI interactions.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        app = XCUIApplication(url: URL(fileURLWithPath: try XCTUnwrap(environment["SCREENSHOT_APP"])))
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testVisiblePages() throws {
        for appearance in ["light", "dark"] {
            launchFixture("-io.github.yamakze.TiebaPureMac.appearance", appearance)
            let row = app.descendants(matching: .any)["thread-1001-0"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            XCTAssertTrue(app.descendants(matching: .any)["thread-1101-0"].firstMatch.waitForExistence(timeout: 10))
            capture("01-home-\(appearance)")
            row.click()
            let replies = app.descendants(matching: .any)["replies-2002"].firstMatch
            XCTAssertTrue(replies.waitForExistence(timeout: 15))
            capture("02-thread-\(appearance)")
            replies.click()
            XCTAssertTrue(app.staticTexts["楼中楼合成回复一"].waitForExistence(timeout: 10))
            capture("03-subposts-\(appearance)")
            XCTAssertTrue(app.staticTexts["连续加载的第三楼回复"].exists)
            app.buttons["close-subposts"].click()
            if appearance == "light" {
                app.typeKey("[", modifierFlags: .command)
                XCTAssertTrue(row.waitForExistence(timeout: 10))
                app.typeKey("]", modifierFlags: .command)
                XCTAssertTrue(replies.waitForExistence(timeout: 10))
            }
            app.buttons["chevron.backward"].click()
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            app.typeKey("2", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["最近访问"].waitForExistence(timeout: 10))
            let query = app.toolbars.searchFields.firstMatch
            XCTAssertTrue(query.waitForExistence(timeout: 10))
            capture("04-forum-entry-\(appearance)")
            query.click()
            query.typeText("Swift\r")
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            capture("05-forum-\(appearance)")
            app.typeKey("3", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["历史搜索词"].waitForExistence(timeout: 10))
            capture("06-search-entry-\(appearance)")
            app.typeKey("f", modifierFlags: .command)
            app.typeText("Swift\r")
            XCTAssertTrue(app.descendants(matching: .any)["thread-1001-2002"].firstMatch.waitForExistence(timeout: 10))
            capture("07-search-\(appearance)")
            app.buttons["account-login"].click()
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
            // Third-party content is not a fixture: wait for the form, then capture
            // its actual state even if the remote page cannot finish loading.
            if app.webViews.textFields.firstMatch.waitForExistence(timeout: 15) == false {
                let note = XCTAttachment(string: "Baidu login form did not become available. Screenshot records the current WebKit state.")
                note.name = "login-form-unavailable-\(appearance)"
                note.lifetime = .keepAlways
                add(note)
            }
            capture("08-login-\(appearance)")
            app.buttons["关闭"].click()
            app.typeKey(",", modifierFlags: .command)
            let settings = app.windows.containing(.popUpButton, identifier: "settings-appearance").firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 10))
            XCTAssertTrue(settings.staticTexts["软件更新"].exists)
            XCTAssertTrue(settings.staticTexts["关于"].exists)
            capture("09-settings-\(appearance)", window: settings)
        }
        for state in ["EMPTY", "ERROR", "LOADING"] {
            launchFixture("SCREENSHOT_\(state)", "-io.github.yamakze.TiebaPureMac.appearance", "light")
            if state == "EMPTY" { XCTAssertTrue(app.staticTexts["暂无帖子"].waitForExistence(timeout: 10)) }
            if state == "ERROR" { XCTAssertTrue(app.staticTexts["网络不可用，请检查网络连接。"].waitForExistence(timeout: 10)) }
            if state == "LOADING" { XCTAssertTrue(app.descendants(matching: .any)["reader-loading"].firstMatch.waitForExistence(timeout: 10)) }
            capture("10-home-\(state.lowercased())")
        }
    }

    func testPaginationRetryAndAccount() {
        launchFixture("SCREENSHOT_PAGINATION", "SCREENSHOT_ACCOUNT")
        let retry = app.descendants(matching: .any)["reader-retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["thread-1001-0"].firstMatch.exists)
        capture("11-home-pagination-retry")
        retry.click()
        XCTAssertTrue(app.descendants(matching: .any)["thread-1101-0"].firstMatch.waitForExistence(timeout: 10))

        let account = app.descendants(matching: .any)["account-menu"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        capture("12-home-account")
        account.click()
        app.menuItems["个人主页"].click()
        XCTAssertTrue(app.staticTexts["粉丝"].waitForExistence(timeout: 10))
        capture("13-account-profile")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        account.click()
        app.menuItems["退出登录"].click()
        XCTAssertTrue(app.buttons["account-login"].waitForExistence(timeout: 10))
    }

    func testWindowCommandsAndHistory() {
        launchFixture("SCREENSHOT_REFRESH")
        let first = app.descendants(matching: .any)["thread-1001-0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertFalse(app.toolbars.buttons["刷新"].exists)
        let viewMenu = app.menuBars.menuBarItems["显示"]
        XCTAssertTrue(viewMenu.exists)
        viewMenu.click()
        XCTAssertTrue(viewMenu.menuItems["刷新"].isEnabled)
        XCTAssertTrue(viewMenu.menuItems["外观"].exists)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["thread-1099-0"].firstMatch.waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: .command)
        let query = app.toolbars.searchFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        app.typeText("draft")
        XCTAssertEqual(query.value as? String, "draft")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.typeText("x")
        XCTAssertNotEqual(query.value as? String, "draftx")
        app.buttons["清空历史"].click()
        XCTAssertTrue(app.staticTexts["暂无搜索记录"].waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.windows["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(query.waitForNonExistence(timeout: 5))
    }

    private func launchFixture(_ arguments: String...) {
        app.launchArguments = ["SCREENSHOT_FIXTURES"] + arguments
        app.launch()
        let reader = app.windows["首页"]
        if !reader.waitForExistence(timeout: 2) {
            // XCTest can reopen the fixture without a restored window.
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(reader.waitForExistence(timeout: 10), "The reader window did not open.")
        }
    }

    private func capture(_ name: String, window: XCUIElement? = nil) {
        let screenshot = (window ?? app.windows.firstMatch).screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
