// Copyright © 2020 Brad Howes. All rights reserved.

import XCTest
@testable import SoundFontsFramework

class ChangesCompilerTests: XCTestCase {

    func testRecent() {
        let found = ChangesCompiler.compile(since: "2.20.4")
        XCTAssertTrue(found.count == 1)
    }

    func testPast() {
        let found = ChangesCompiler.compile(since: "2.18.3")
        XCTAssertTrue(found.count == 4)
    }
}