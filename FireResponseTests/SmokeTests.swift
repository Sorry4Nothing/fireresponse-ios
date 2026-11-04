import Foundation
import Testing
@testable import FireResponse

struct SmokeTests {
    @Test func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "ch.fireresponse.app")
    }
}
