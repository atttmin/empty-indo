import XCTest

#if os(iOS)
final class MobileExperienceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayTabShowsRecapPulseAndCardsShortcut() throws {
        let app = launch([
            "-ScreenshotSeed",
        ])

        XCTAssertTrue(app.staticTexts["今日伴读"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["今日节奏"].waitForExistence(timeout: 8))

        app.buttons["tab.cards"].tap()
        XCTAssertTrue(app.staticTexts["卡片"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardsOpenVocabAndHighlightDetails() throws {
        let app = launch([
            "-ScreenshotSeed",
            "-ScreenshotSeedStudyData",
            "-OpenTabCards",
        ])

        XCTAssertTrue(app.buttons["cards.vocab.detail"].waitForExistence(timeout: 12))
        app.buttons["cards.vocab.detail"].tap()
        XCTAssertTrue(app.staticTexts["释义"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["原句"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        scrollToElement(app.buttons["cards.highlight.detail"], in: app)
        XCTAssertTrue(app.buttons["cards.highlight.detail"].waitForExistence(timeout: 5))
        app.buttons["cards.highlight.detail"].tap()
        XCTAssertTrue(app.staticTexts["高亮详情"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
    }

    @MainActor
    func testCardsOpenFlashcardReviewAndMobileGraph() throws {
        let app = launch([
            "-ScreenshotSeed",
            "-ScreenshotSeedStudyData",
            "-OpenTabCards",
        ])

        XCTAssertTrue(app.buttons["cards.flashcards.open"].waitForExistence(timeout: 12))
        app.buttons["cards.flashcards.open"].tap()
        XCTAssertTrue(app.staticTexts["沉浸式闪卡"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        let graphButton = app.buttons["cards.graph.open"]
        scrollToElement(graphButton, in: app)
        XCTAssertTrue(graphButton.waitForExistence(timeout: 8))
        graphButton.tap()
        XCTAssertTrue(app.staticTexts["移动图谱"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardsDetailJumpBackToReader() throws {
        let app = launch([
            "-ScreenshotSeed",
            "-ScreenshotSeedStudyData",
            "-OpenTabCards",
        ])

        XCTAssertTrue(app.buttons["cards.vocab.detail"].waitForExistence(timeout: 12))
        app.buttons["cards.vocab.detail"].tap()
        XCTAssertTrue(app.buttons["cards.vocab.detail.jump"].waitForExistence(timeout: 5))
        app.buttons["cards.vocab.detail.jump"].tap()

        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["思维之书"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testReaderCompanionOpensFromReaderShell() throws {
        let app = launch([
            "-ScreenshotSeed",
            "-OpenReader",
        ])

        XCTAssertTrue(app.buttons["tab.companion"].waitForExistence(timeout: 12))
        app.buttons["tab.companion"].tap()

        XCTAssertTrue(app.staticTexts["AI 伴读"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["就这一页,问点什么…"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPDFReaderSmokePath() throws {
        let app = launch([
            "-ScreenshotSeed",
            "-ScreenshotSeedPDF",
            "-OpenPDFReader",
        ])

        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["纸页样本"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reader.search"].waitForExistence(timeout: 5))
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) {
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
    }
}
#endif
