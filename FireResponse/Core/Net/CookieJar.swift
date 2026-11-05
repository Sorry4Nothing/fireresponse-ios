import Foundation

/// URLSession führt hier kein Cookie-Jar: Die App hält die Cookies als Text `name=wert; name2=wert2` in der Keychain.
nonisolated enum CookieJar {
    /// Übernimmt die Cookies aus dem (zusammengefassten) `Set-Cookie`-Header, ohne Attribute.
    /// Abgelaufene Cookies (`Max-Age=0`, `Expires` in der Vergangenheit) löschen das gleichnamige.
    static func merge(current: String?, setCookie: String?, url: URL, now: Date = .now) -> String? {
        var pairs: [(name: String, value: String)] = (current ?? "").components(separatedBy: "; ").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }
        if let setCookie {
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookie], for: url) {
                pairs.removeAll { $0.name == cookie.name }
                if let expires = cookie.expiresDate, expires <= now { continue }
                pairs.append((cookie.name, cookie.value))
            }
        }
        return pairs.isEmpty ? nil : pairs.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
