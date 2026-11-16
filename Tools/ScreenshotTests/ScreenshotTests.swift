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
            app.launchArguments = ["SCREENSHOT_FIXTURES", "-io.github.yamakze.TiebaPureMac.appearance", appearance]
            app.launch()
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "确定性主帖：回复筛选与媒体布局")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            capture("01-home-\(appearance)")
            row.click()
            let replies = app.descendants(matching: .any)["replies-2002"].firstMatch
            XCTAssertTrue(replies.waitForExistence(timeout: 15))
            capture("02-thread-\(appearance)")
            replies.click()
            XCTAssertTrue(app.staticTexts["楼中楼合成回复一"].waitForExistence(timeout: 10))
            capture("03-subposts-\(appearance)")
            app.buttons["关闭"].click()
            app.buttons["chevron.backward"].click()
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            // Switching section clears the thread route; no list and detail coexist.
            app.staticTexts["section-forum"].click()
            let query = app.textFields["reader-query"]
            XCTAssertTrue(query.waitForExistence(timeout: 10))
            capture("04-forum-entry-\(appearance)")
            query.click()
            query.typeText("Swift")
            app.buttons["打开"].click()
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            capture("05-forum-\(appearance)")
            app.staticTexts["section-search"].click()
            XCTAssertTrue(query.waitForExistence(timeout: 10))
            capture("06-search-entry-\(appearance)")
            query.click()
            query.typeText("Swift")
            app.buttons["搜索"].click()
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Swift 的确定性搜索结果")).firstMatch.waitForExistence(timeout: 10))
            capture("07-search-\(appearance)")
            app.buttons["登录百度账号"].click()
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
            XCTAssertTrue(app.popUpButtons.firstMatch.waitForExistence(timeout: 10))
            capture("09-settings-\(appearance)", window: app.windows.containing(.staticText, identifier: "版本").firstMatch)
            app.terminate()
        }
        for state in ["EMPTY", "ERROR", "LOADING"] {
            app.launchArguments = ["SCREENSHOT_FIXTURES", "SCREENSHOT_\(state)", "-io.github.yamakze.TiebaPureMac.appearance", "light"]
            app.launch()
            if state == "EMPTY" { XCTAssertTrue(app.staticTexts["暂无帖子"].waitForExistence(timeout: 10)) }
            if state == "ERROR" { XCTAssertTrue(app.staticTexts["网络不可用，请检查网络连接。"].waitForExistence(timeout: 10)) }
            if state == "LOADING" { XCTAssertTrue(app.descendants(matching: .any)["reader-loading"].firstMatch.waitForExistence(timeout: 10)) }
            capture("10-home-\(state.lowercased())")
            app.terminate()
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
