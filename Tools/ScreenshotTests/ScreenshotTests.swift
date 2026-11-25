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
            XCTAssertTrue(row.isPresent(within: 15))
            XCTAssertTrue(app.descendants(matching: .any)["thread-1101-0"].firstMatch.isPresent(within: 10))
            capture("01-home-\(appearance)")
            row.click()
            let replies = app.descendants(matching: .any)["replies-2002"].firstMatch
            XCTAssertTrue(replies.isPresent(within: 15))
            XCTAssertTrue(app.staticTexts["楼主"].firstMatch.exists)
            capture("02-thread-\(appearance)")
            replies.click()
            XCTAssertTrue(app.staticTexts["楼中楼合成回复一"].isPresent(within: 10))
            capture("03-subposts-\(appearance)")
            XCTAssertTrue(app.staticTexts["连续加载的第三楼回复"].exists)
            app.buttons["close-subposts"].click()
            if appearance == "light" {
                app.typeKey("[", modifierFlags: .command)
                XCTAssertTrue(row.isPresent(within: 10))
                app.typeKey("]", modifierFlags: .command)
                XCTAssertTrue(replies.isPresent(within: 10))
            }
            app.toolbars.buttons["back-to-thread-list"].firstMatch.click()
            XCTAssertTrue(row.isPresent(within: 10))
            app.typeKey("2", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["最近访问"].isPresent(within: 10))
            let query = app.toolbars.searchFields.firstMatch
            XCTAssertTrue(query.isPresent(within: 10))
            capture("04-forum-entry-\(appearance)")
            query.click()
            query.typeText("Swift\r")
            XCTAssertTrue(row.isPresent(within: 10))
            capture("05-forum-\(appearance)")
            app.typeKey("3", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["历史搜索词"].isPresent(within: 10))
            capture("06-search-entry-\(appearance)")
            XCTAssertTrue(query.isPresent(within: 10))
            query.click()
            query.typeText("Swift\r")
            XCTAssertTrue(app.descendants(matching: .any)["thread-1001-2002"].firstMatch.isPresent(within: 10))
            capture("07-search-\(appearance)")
            app.buttons["account-login"].click()
            XCTAssertTrue(app.webViews.firstMatch.isPresent(within: 15))
            // Third-party content is not a fixture: wait for the form, then capture
            // its actual state even if the remote page cannot finish loading.
            if app.webViews.textFields.firstMatch.isPresent(within: 15) == false {
                let note = XCTAttachment(string: "Baidu login form did not become available. Screenshot records the current WebKit state.")
                note.name = "login-form-unavailable-\(appearance)"
                note.lifetime = .keepAlways
                add(note)
            }
            capture("08-login-\(appearance)")
            app.buttons["关闭"].click()
            app.typeKey(",", modifierFlags: .command)
            let settings = app.windows.containing(.popUpButton, identifier: "settings-appearance").firstMatch
            XCTAssertTrue(settings.isPresent(within: 10))
            XCTAssertTrue(settings.staticTexts["软件更新"].exists)
            XCTAssertTrue(settings.staticTexts["关于"].exists)
            capture("09-settings-\(appearance)", window: settings)
        }
        for state in ["EMPTY", "ERROR", "LOADING"] {
            launchFixture("SCREENSHOT_\(state)", "-io.github.yamakze.TiebaPureMac.appearance", "light")
            if state == "EMPTY" { XCTAssertTrue(app.staticTexts["暂无帖子"].isPresent(within: 10)) }
            if state == "ERROR" { XCTAssertTrue(app.staticTexts["网络不可用，请检查网络连接。"].isPresent(within: 10)) }
            if state == "LOADING" { XCTAssertTrue(app.descendants(matching: .any)["reader-loading"].firstMatch.isPresent(within: 10)) }
            capture("10-home-\(state.lowercased())")
        }
    }

    func testPaginationRetryAndAccount() {
        launchFixture("SCREENSHOT_PAGINATION", "SCREENSHOT_ACCOUNT")
        let retry = app.descendants(matching: .any)["reader-retry"].firstMatch
        XCTAssertTrue(retry.isPresent(within: 10))
        XCTAssertTrue(app.descendants(matching: .any)["thread-1001-0"].firstMatch.exists)
        capture("11-home-pagination-retry")
        retry.click()
        XCTAssertTrue(app.descendants(matching: .any)["thread-1101-0"].firstMatch.isPresent(within: 10))

        let account = app.descendants(matching: .any)["account-menu"].firstMatch
        XCTAssertTrue(account.isPresent(within: 10))
        capture("12-home-account")
        account.click()
        app.menuItems["个人主页"].click()
        XCTAssertTrue(app.staticTexts["粉丝"].isPresent(within: 10))
        capture("13-account-profile")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        account.click()
        app.menuItems["退出登录"].click()
        XCTAssertTrue(app.buttons["account-login"].isPresent(within: 10))
    }

    func testWindowCommandsAndHistory() {
        launchFixture("SCREENSHOT_REFRESH")
        let first = app.descendants(matching: .any)["thread-1001-0"].firstMatch
        XCTAssertTrue(first.isPresent(within: 10))
        XCTAssertFalse(app.toolbars.buttons["刷新"].exists)
        let viewMenu = app.menuBars.menuBarItems["显示"]
        XCTAssertTrue(viewMenu.exists)
        viewMenu.click()
        XCTAssertTrue(viewMenu.menuItems["刷新"].isEnabled)
        XCTAssertTrue(viewMenu.menuItems["外观"].exists)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["thread-1099-0"].firstMatch.isPresent(within: 10))

        app.typeKey("f", modifierFlags: .command)
        let query = app.toolbars.searchFields.firstMatch
        XCTAssertTrue(query.isPresent(within: 10))
        app.typeText("draft")
        XCTAssertEqual(query.value as? String, "draft")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.typeText("x")
        XCTAssertNotEqual(query.value as? String, "draftx")
        let keyword = app.buttons["macOS"]
        XCTAssertTrue(keyword.isPresent(within: 5))
        keyword.rightClick()
        app.menuItems["删除此记录"].click()
        XCTAssertTrue(keyword.isAbsent(within: 5))
        XCTAssertTrue(app.buttons["SwiftUI"].exists)
        app.buttons["清空历史"].click()
        XCTAssertTrue(app.staticTexts["暂无搜索记录"].isPresent(within: 10))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.windows["首页"].isPresent(within: 5))
        XCTAssertTrue(query.isAbsent(within: 5))
    }

    func testForumSearchAndAccountLibrary() {
        launchFixture("SCREENSHOT_ACCOUNT", "UITEST_SEED_ACCOUNT_COLLECTION",
                      "-io.github.yamakze.TiebaPureMac.appearance", "light")
        let homeRow = app.descendants(matching: .any)["thread-1001-0"].firstMatch
        XCTAssertTrue(homeRow.isPresent(within: 10))

        let followed = app.descendants(matching: .any)["section-followedForums"].firstMatch
        XCTAssertTrue(followed.isPresent(within: 10))
        followed.click()
        let forum = app.buttons["followed-forum-101"]
        if !forum.isPresent(within: 3) {
            followed.click()
        }
        XCTAssertTrue(forum.isPresent(within: 10))
        capture("16-followed-forums")
        forum.click()
        let unfollow = app.toolbars.buttons["forum-unfollow"].firstMatch
        let follow = app.toolbars.buttons["forum-follow"].firstMatch
        XCTAssertTrue(unfollow.isPresent(within: 10))
        unfollow.click()
        XCTAssertTrue(follow.isPresent(within: 10))
        followed.click()
        XCTAssertTrue(app.buttons["followed-forum-102"].isPresent(within: 10))
        XCTAssertFalse(forum.exists)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(follow.isPresent(within: 10))
        follow.click()
        XCTAssertTrue(unfollow.isPresent(within: 10))
        followed.click()
        XCTAssertTrue(forum.isPresent(within: 10))
        forum.click()

        app.typeKey("2", modifierFlags: [.command, .option])
        let publishSorted = app.descendants(matching: .any)["thread-8003-0"].firstMatch
        XCTAssertTrue(publishSorted.isPresent(within: 10))
        app.typeKey("3", modifierFlags: [.command, .option])
        let featured = app.descendants(matching: .any)["thread-8001-0"].firstMatch
        XCTAssertTrue(featured.isPresent(within: 10))
        capture("14-forum-featured")

        let query = app.toolbars.searchFields.firstMatch
        XCTAssertTrue(query.isPresent(within: 10))
        XCTAssertFalse(app.toolbars.buttons["search-current-forum"].exists)
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Swift\r")
        XCTAssertTrue(app.descendants(matching: .any)["thread-1003-2002"].firstMatch.isPresent(within: 10))
        app.typeKey("2", modifierFlags: [.command, .option])
        XCTAssertTrue(app.descendants(matching: .any)["thread-1004-2002"].firstMatch.isPresent(within: 10))
        XCTAssertFalse(app.toolbars.descendants(matching: .any)["search-order"].exists)
        capture("15-forum-search")
        query.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(featured.isPresent(within: 10))
        chooseViewOption("只看精华", in: "吧内主题排序")
        XCTAssertTrue(publishSorted.isPresent(within: 10))
        app.toolbars.buttons["back-to-forum-entry"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["最近访问"].isPresent(within: 10))

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["历史搜索词"].isPresent(within: 10))
        XCTAssertFalse(app.buttons["Swift"].exists)
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Swift\r")
        XCTAssertTrue(app.descendants(matching: .any)["thread-1001-2002"].firstMatch.isPresent(within: 10))
        chooseViewOption("相关", in: "搜索结果排序")
        XCTAssertTrue(app.descendants(matching: .any)["thread-1002-2002"].firstMatch.isPresent(within: 10))
        chooseViewOption("最新", in: "搜索结果排序")
        XCTAssertTrue(app.descendants(matching: .any)["thread-1001-2002"].firstMatch.isPresent(within: 10))

        let library = app.descendants(matching: .any)["section-favorites"].firstMatch
        library.click()
        let marked = app.descendants(matching: .any)["thread-1001-0"].firstMatch
        XCTAssertTrue(marked.isPresent(within: 10))
        capture("17-favorites")
        marked.click()
        let reply = app.staticTexts["已定位搜索命中回复"]
        XCTAssertTrue(reply.isPresent(within: 10))
        let onlyAuthor = app.descendants(matching: .any)["only-thread-author"].firstMatch
        onlyAuthor.click()
        XCTAssertTrue(reply.isAbsent(within: 10))
        XCTAssertTrue(app.staticTexts["楼主"].firstMatch.isPresent(within: 10))
        XCTAssertFalse(app.descendants(matching: .any)["replies-2002"].firstMatch.exists)
        capture("18-thread-author")
        onlyAuthor.click()
        XCTAssertTrue(app.staticTexts["确定性回复内容"].isPresent(within: 10))

        let unfavorite = app.toolbars.buttons["thread-unfavorite"].firstMatch
        let favorite = app.toolbars.buttons["thread-favorite"].firstMatch
        XCTAssertTrue(unfavorite.isPresent(within: 10))
        unfavorite.click()
        XCTAssertTrue(favorite.isPresent(within: 10))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["暂无收藏"].isPresent(within: 10))
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(favorite.isPresent(within: 10))
        favorite.click()
        XCTAssertTrue(unfavorite.isPresent(within: 10))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(marked.isPresent(within: 10))

        let account = app.descendants(matching: .any)["account-menu"].firstMatch
        account.click()
        app.menuItems["退出登录"].click()
        XCTAssertTrue(library.isAbsent(within: 10))
        XCTAssertTrue(app.windows["首页"].isPresent(within: 10))
    }

    func testReaderContinuityAndImagePreview() throws {
        launchFixture("SCREENSHOT_READING_CONTINUITY", "-io.github.yamakze.TiebaPureMac.appearance", "light")
        let homeList = app.scrollViews["reader-thread-list"].firstMatch
        XCTAssertTrue(homeList.isPresent(within: 10))
        let homeFirst = app.buttons["thread-1001-0"].firstMatch
        XCTAssertTrue(homeFirst.isPresent(within: 10))
        let nextPage = app.buttons["thread-1101-0"].firstMatch
        XCTAssertFalse(nextPage.exists)
        homeList.scroll(byDeltaX: 0, deltaY: -670)
        let homeRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "thread-"))
        let topHomeRow = try XCTUnwrap(topVisibleElement(matching: homeRows, in: homeList)).identifier
        XCTAssertNotEqual(topHomeRow, homeFirst.identifier)

        app.typeKey("2", modifierFlags: .command)
        let query = app.toolbars.searchFields.firstMatch
        query.click()
        query.typeText("Swift\r")
        XCTAssertTrue(app.toolbars.buttons["back-to-forum-entry"].firstMatch.isPresent(within: 10))
        app.typeKey("f", modifierFlags: .command)
        app.typeText("local\r")
        let hit = app.descendants(matching: .any)["thread-1003-2002"].firstMatch
        XCTAssertTrue(hit.isPresent(within: 10))
        hit.click()
        let floors = app.scrollViews["thread-floors"].firstMatch
        XCTAssertTrue(floors.isPresent(within: 10))
        XCTAssertTrue(app.staticTexts["已定位搜索命中回复"].isPresent(within: 10))
        floors.scroll(byDeltaX: 0, deltaY: -950)
        let floorNumbers = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "post-floor-"))
        let topFloor = try XCTUnwrap(topVisibleElement(matching: floorNumbers, in: floors)).identifier
        XCTAssertGreaterThan(topFloor, "post-floor-2003")

        app.typeKey("3", modifierFlags: .command)
        app.typeKey("f", modifierFlags: .command)
        app.typeText("global\r")
        let global = app.descendants(matching: .any)["thread-1001-2002"].firstMatch
        XCTAssertTrue(global.isPresent(within: 10))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts[topFloor].isPresent(within: 10))
        XCTAssertLessThan(app.staticTexts[topFloor].frame.midY, floors.frame.midY)
        XCTAssertGreaterThanOrEqual(app.staticTexts[topFloor].frame.midY, floors.frame.minY)
        let onlyAuthor = app.checkBoxes["only-thread-author"].firstMatch
        onlyAuthor.click()
        XCTAssertTrue(app.staticTexts[topFloor].isAbsent(within: 10))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(global.isPresent(within: 10))
        app.descendants(matching: .any)["section-forum"].firstMatch.click()
        XCTAssertTrue(onlyAuthor.isPresent(within: 10))
        XCTAssertEqual(onlyAuthor.value as? Int, 1)
        XCTAssertFalse(app.staticTexts[topFloor].exists)
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(hit.isPresent(within: 10))
        XCTAssertEqual(query.value as? String, "local")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(global.isPresent(within: 10))
        XCTAssertEqual(query.value as? String, "global")

        app.typeKey("2", modifierFlags: .command)
        app.typeKey("f", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("anchored\r")
        let lateHit = app.buttons["thread-1003-2012"].firstMatch
        XCTAssertTrue(lateHit.isPresent(within: 10))
        lateHit.click()
        let firstReply = app.staticTexts["post-floor-2002"]
        XCTAssertTrue(app.staticTexts["post-floor-2012"].isPresent(within: 10))
        XCTAssertFalse(firstReply.exists)
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(firstReply.isPresent(within: 10))

        app.typeKey("1", modifierFlags: .command)
        let restoredRow = app.buttons[topHomeRow].firstMatch
        XCTAssertTrue(restoredRow.isPresent(within: 10))
        XCTAssertLessThan(restoredRow.frame.midY, homeList.frame.midY)
        XCTAssertGreaterThanOrEqual(restoredRow.frame.midY, homeList.frame.minY)
        homeList.scroll(byDeltaX: 0, deltaY: -5000)
        XCTAssertTrue(nextPage.isPresent(within: 10))
        homeList.scroll(byDeltaX: 0, deltaY: 1700)
        XCTAssertTrue(homeFirst.isPresent(within: 10))
        homeFirst.click()

        let image = app.buttons["post-image-2"].firstMatch
        XCTAssertTrue(image.isPresent(within: 10))
        image.click()
        let preview = app.images["image-preview-display"].firstMatch
        XCTAssertTrue(preview.isPresent(within: 10))
        let position = app.staticTexts["image-preview-position"].firstMatch
        XCTAssertEqual(position.value as? String, "1 / 2")
        capture("19-image-preview")
        let zoom = app.buttons["image-preview-zoom-in"].firstMatch
        XCTAssertTrue(zoom.isEnabled)
        zoom.click()
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertEqual(position.value as? String, "2 / 2")
        let retry = app.buttons["image-preview-retry"].firstMatch
        XCTAssertTrue(retry.isPresent(within: 10))
        XCTAssertTrue(preview.isPresent(within: 10))
        capture("20-image-preview-retry")
        retry.click()
        XCTAssertTrue(retry.isPresent(within: 10))
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        XCTAssertEqual(position.value as? String, "1 / 2")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(app.buttons["image-preview-close"].isAbsent(within: 10))
        XCTAssertTrue(image.isHittable)

        floors.scroll(byDeltaX: 0, deltaY: -350)
        let replies = app.descendants(matching: .any)["replies-2002"].firstMatch
        XCTAssertTrue(replies.isPresent(within: 10))
        replies.click()
        let inlineReplyImage = app.buttons["post-image-1"].firstMatch
        XCTAssertTrue(inlineReplyImage.isPresent(within: 10))
        inlineReplyImage.click()
        XCTAssertTrue(preview.isPresent(within: 10))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(app.buttons["image-preview-close"].isAbsent(within: 10))
        XCTAssertTrue(app.buttons["close-subposts"].isPresent(within: 10))
    }

    private func topVisibleElement(matching query: XCUIElementQuery, in scrollView: XCUIElement) -> XCUIElement? {
        let bounds = scrollView.frame
        return query.allElementsBoundByIndex
            .filter { $0.frame.midY >= bounds.minY && $0.frame.midY < bounds.midY }
            .min { $0.frame.minY < $1.frame.minY }
    }

    private func chooseViewOption(_ option: String, in submenu: String) {
        let viewMenu = app.menuBars.menuBarItems["显示"]
        viewMenu.click()
        viewMenu.menuItems[submenu].firstMatch.hover()
        XCTAssertTrue(app.menuItems[option].isPresent(within: 5))
        app.menuItems[option].click()
    }

    private func launchFixture(_ arguments: String...) {
        app.launchArguments = ["SCREENSHOT_FIXTURES"] + arguments
        app.launch()
        let reader = app.windows["首页"]
        if !reader.isPresent(within: 2) {
            // XCTest can reopen the fixture without a restored window.
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(reader.isPresent(within: 10), "The reader window did not open.")
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

private extension XCUIElement {
    // Check the current accessibility snapshot before XCTest starts polling.
    func isPresent(within timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    func isAbsent(within timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }
}
