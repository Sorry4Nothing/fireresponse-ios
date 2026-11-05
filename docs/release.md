# Release

Bau, Signieren und Upload laufen lokal auf dem Mac mit Xcode. Die CI baut, lintet und testet nur.

## Voraussetzungen

- `Config/Local.xcconfig` (aus `Local.example.xcconfig`, nicht im Repo): `API_BASE_URL` und `DEVELOPMENT_TEAM`.
- `GoogleService-Info.plist` aus dem Firebase-Projekt im Ordner `FireResponse/` (nicht im Repo, in `.gitignore`). Ohne sie läuft die App ohne Push.
- APNs-Schlüssel im Firebase-Projekt hinterlegt; das Provisioning-Profil enthält «Push Notifications». `aps-environment` steht in `Config/FireResponse.entitlements` auf `development`; Xcode setzt beim Archivieren `production`.

## Archiv

1. Auf `main` ist der Stand, der ausgeliefert wird (Release-PR von `develop` nach `main`, Merge-Commit).
2. `MARKETING_VERSION` und `CURRENT_PROJECT_VERSION` in den Build-Einstellungen erhöhen.
3. Xcode: Product → Archive (Schema `FireResponse`, Release), dann Distribute App → App Store Connect.
4. In App Store Connect: Datenschutz-Angaben «Keine Daten zum Tracking», Altersfreigabe, Support- und Datenschutz-Adresse der API (`/support`, `/datenschutz`).

## Vor dem Upload prüfen

- Basis-URL im Archiv ist die der Produktion (Info.plist des Archivs, Schlüssel `APIBaseURL`).
- Kein Fake-Backend: der Release-Build enthält es nicht (`#if DEBUG`).
- Gerät mit englischer Systemsprache: Texte bleiben deutsch.
- Checkliste Barrierefreiheit aus dem Backend-Repo (`docs/barrierefreiheit.md`) auf einem Gerät mit VoiceOver.
