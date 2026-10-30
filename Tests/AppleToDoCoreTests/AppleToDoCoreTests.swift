@testable import AppleToDoCore
import XCTest

final class AppleToDoCoreTests: XCTestCase {
    func testVersionFollowsSemver() {
        let pattern = #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#
        XCTAssertNotNil(AppleToDoCore.version.range(of: pattern, options: .regularExpression))
    }
}
