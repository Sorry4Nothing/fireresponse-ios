import Foundation
import Testing
@testable import FireResponse

struct CookieJarTests {
    let url = URL(string: "https://api.example.org/api/auth/sign-in/username")!

    @Test func addsAndReplacesCookies() {
        let merged = CookieJar.merge(current: "a=1; b=2", setCookie: "b=3; Path=/; HttpOnly, c=4; Path=/; Max-Age=100", url: url)
        #expect(Set((merged ?? "").components(separatedBy: "; ")) == ["a=1", "b=3", "c=4"])
    }

    @Test func maxAgeZeroDeletes() {
        #expect(CookieJar.merge(current: "a=1; b=2", setCookie: "a=; Path=/; Max-Age=0", url: url) == "b=2")
        #expect(CookieJar.merge(current: "a=1", setCookie: "a=; Path=/; Max-Age=0", url: url) == nil)
    }

    @Test func pastExpiresDeletes() {
        let merged = CookieJar.merge(current: "a=1", setCookie: "a=x; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT", url: url)
        #expect(merged == nil)
    }

    @Test func withoutSetCookieNothingChanges() {
        #expect(CookieJar.merge(current: "a=1", setCookie: nil, url: url) == "a=1")
        #expect(CookieJar.merge(current: nil, setCookie: nil, url: url) == nil)
    }

    @Test func secureAndPrefixedCookiesAreKept() {
        let merged = CookieJar.merge(current: nil, setCookie: "__Secure-better-auth.session_token=tok.sig%3D; Path=/; Secure; HttpOnly; SameSite=Lax", url: url)
        #expect(merged == "__Secure-better-auth.session_token=tok.sig%3D")
    }
}
