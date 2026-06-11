//
//  EndToEndSmokeTests.swift
//  EmptyUITests
//
//  Product-flow smoke tests that avoid network/AI dependencies: seeded book,
//  reader chrome, saved highlight, export sheet, and copy action.
//

import XCTest

final class EndToEndSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSeededReaderHighlightExportFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ScreenshotSeed",
            "-ScreenshotSeedHighlight",
            "-OpenReader",
            "-OpenHighlights",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["‹ 书库"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["思维之书"].firstMatch.waitForExistence(timeout: 8))

        XCTAssertTrue(app.staticTexts["高亮 · 朱批"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["跳回原文"].firstMatch.waitForExistence(timeout: 8))

        let export = app.buttons["导出"]
        XCTAssertTrue(export.waitForExistence(timeout: 8))
        export.tap()

        XCTAssertTrue(app.staticTexts["导出摘录"].waitForExistence(timeout: 8))
        let copyAll = app.buttons["复制全部"]
        XCTAssertTrue(copyAll.waitForExistence(timeout: 8))
        copyAll.tap()
        XCTAssertTrue(app.buttons["已复制 ✓"].waitForExistence(timeout: 4))
    }
}
