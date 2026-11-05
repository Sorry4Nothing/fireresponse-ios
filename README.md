# FireResponse iOS

Native iOS-App (Swift, SwiftUI) für FireResponse, die App für Jugend- und Kinderfeuerwehren im Kanton Zürich: Übungen aus Lodur, Ja/Nein-Anmeldung, Kontakt und Push.

Das Backend liegt in [Sorry4Nothing/fireresponse-api](https://github.com/Sorry4Nothing/fireresponse-api). Die API-Beschreibung steht dort unter `docs/api/`. Die Schwester-App ist [Sorry4Nothing/fireresponse-android](https://github.com/Sorry4Nothing/fireresponse-android).

## Bauen und prüfen

Voraussetzung: Xcode 27, iOS 26 als Mindestversion, nur iPhone. Optional `swiftlint` (`brew install swiftlint`).

```
cp Config/Local.example.xcconfig Config/Local.xcconfig   # Basis-URL und Team eintragen, nicht im Repo
swiftlint --strict
xcodebuild test -project FireResponse.xcodeproj -scheme FireResponse \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Das ist auch der Check `build` der CI (macOS-Runner, ohne Signierung). Bau, Signieren und Upload laufen lokal mit Xcode.

## Ohne Backend ausprobieren

Der Fake-Server läuft nur im Debug-Build und nur auf ausdrücklichen Launch-Parameter: `-FireResponseFakeBackend` und `-FireResponseFakeLogin <demo|eltern|kommando|leer>` (erfundene Konten, Startpasswort steht in `App/DebugFakeBackend.swift`).

## Arbeitsweise

- Ein Branch und ein Pull Request pro Issue, abgezweigt von `develop`: `feature/<nr>-<kurzname>`, für Bugs `fix/<nr>-<kurzname>`.
- `main` und `develop` nimmt nur Pull Requests an, mit grünem Check `build`.
- Design und Abweichungen: [docs/design.md](docs/design.md).
