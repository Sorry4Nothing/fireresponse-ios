# Design

Dieses Dokument hält fest, wie die App das Design des Auftraggebers («Fire-Response iOS») umsetzt und wo sie davon abweicht. Tokens aus dem Design System gehen vor den Mockups.

## Zuordnung Baustein → Code

| Baustein | Code |
|---|---|
| Farb-Tokens (Nacht, Tag, je Mehr Kontrast) | `FireResponse/Assets.xcassets/Colors`, `Design/Colors.swift` (`Color.frSurface` …) |
| Schrift | `Design/Typography.swift`: Barlow Condensed nur für Titel (`relativeTo:`), sonst SF Pro über Textstile |
| Abstände, Grössen, Ecken | `Design/Metrics.swift`: `Spacing`, `Sizes`, `Radius` |
| Button (Haupt, Umriss, Text) | `Components/FRButton.swift`: `FRButton(_:systemImage:kind:action:)` |
| Textfeld, Passwort | `Components/FRTextField.swift`, `FRPasswordField.swift` (Rahmen `FRFieldChrome`) |
| StatusChip | `Components/StatusChip.swift`: `StatusChip(_ kind)` |
| Zusage Ja/Nein | `Components/ResponseControl.swift`: `ResponseControl(name:initials:selection:detail:onSelect:)` |
| Listenzeile | `Components/ListRow.swift`: `ListRow(_:systemImage:value:role:)`, Label von `Toggle`, `NavigationLink`, `Button` |
| Avatar | `Components/Avatar.swift`: `Avatar(initials:size:style:image:)` oder `imageData:` |
| RangAbzeichen | `Components/RangAbzeichen.swift`: `RangAbzeichen(_ imageData:width:stars:)` |
| Hinweis | `Components/Notice.swift`: `Notice(_ kind, title:message:)` |
| Zustand (Laden, Leer, Offline, Fehler, Nicht gefunden, Kein Zugriff, Sitzung abgelaufen, Keine Einheit) | `Components/StateView.swift`: `StateView(_ kind, primary:secondary:)` |
| Kopf mit Titel und Zusatzzeile | `Components/ScreenHeader.swift`: `ScreenHeader(_:subtitle:style:)` |
| Texte | `Localizable.xcstrings` (nur Deutsch), Bausteine nehmen `LocalizedStringResource` |
| Kontrasttest | `FireResponseTests/ContrastTests.swift` (Textpaare 4.5:1, `outline`, `focus`, `switch-on` 3:1, vier Erscheinungen) |

Noch nicht als Baustein umgesetzt: Alert, Sheet, Umschalter, TabBar und NavigationBar (System), Screens.

## Regeln

- Kein Zustand nur über Farbe: immer Symbol und Wort.
- Textpaare mindestens 4.5:1, `outline`, `focus` und `switch-on` mindestens 3:1, in allen vier Erscheinungen.
- Jedes bedienbare Element mindestens 44 × 44 pt. Keine festen Höhen für Text.
- Signalrot (`primary`) nur für die eine Hauptaktion pro Screen.
- Nur iPhone, `de-CH`, native Tab Bar und NavigationStack mit Large Titles.

## Abweichungen

- **Tokens vor Screens:** Initialen ruhiger Avatare nutzen `on-secondary-container` (die Screens zeichnen Nacht `on-secondary-muted`, Tag `accent`). Die Schalterspur ist `switch-on` (die Screens zeichnen in Tag `secondary`). Angleichen muss das Design.
- **VoiceOver bei Zusage:** «Ja für Anna» statt «Anna, Ja», damit das Label mit dem sichtbaren Wort beginnt.
- **Avatargrössen:** 44 und 84 pt (das Design nennt in den READMEs 36 und 40 pt für Zeilen).
- **RangAbzeichen:** `UIImage` liest PNG, kein SVG. Fehlt das Bild oder ist es unlesbar, zeichnet der Baustein den Platzhalter aus `Raenge.md` (das Design lässt die Zeile ohne Abzeichen). Ersetzen, sobald das Original vorliegt.
- **Listenzeile:** Hintergrund (`surface-container-low`) und Schalter-Tint setzt der Aufrufer an der `List`.
- **Entwicklungssprache:** der String Catalog hat `de` als Quellsprache, passend zum Projekt; `de-CH` ist noch nicht gesetzt.

## Push (Issue #6)

- Die Einstellungsseite «Benachrichtigungen» ist im Design nicht gezeichnet. Sie ist aus `ListRow` mit `Toggle` (Tint `switch-on`), `Notice` und `FRButton` gebaut: Schalter «Neue Übungen» und, nur für Personen mit Rolle in einer Einheit, «Neue Anmeldungen». Ein Schalter springt bei einem Fehler zurück und zeigt eine Meldung. Ist das System-Recht aus, steht oben ein Hinweis mit Weg in die Einstellungen; ist noch nie gefragt worden, ein Knopf «Mitteilungen erlauben».
- Das Recht fragt die App nicht beim Start, sondern über `PushCenter.requestAuthorization()` (Einstellungen; der Integrationsschritt ruft es nach dem Willkommen).

## Übungen (Issue #4)

Ordner `FireResponse/Features/Exercises/`: `ExerciseLogic` (Regeln und Formate, rein), `ExerciseModels` (Laden, Antworten, Polling), Ansichten für Liste, Detail und Anmeldungen.

- **Liste:** eine Abfrage für alle eigenen Einheiten (heute bis sechs Monate, die App schickt nie eine Einheit mit), gruppiert nach Schweizer Kalendertag, ab AX1 Datum über den Karten. Kein Rang auf der Karte. `.refreshable`.
- **Anmeldefenster:** Knöpfe nur bei `teilnahmeOffen`; sonst «Anmeldung ab <Datum>» (`anmeldungAb`, nur wenn aktiv), sonst «Die Anmeldung ist geschlossen» mit dem Stand als Chip. Die App rechnet das Fenster nie selbst. `anmeldbar` steuert nichts mehr (API #194: immer `true`); «Termine ohne Anmeldung» und `KEINE_ANMELDUNG` entfallen. Termine «nur Leitende» fehlen für Eltern in Liste und Detail; ein 404 auf ein Detail zeigt «Nicht gefunden».
- **Antworten:** Ja/Nein je teilnehmende Person (`ResponseControl`) und für Leitende selbst (`setLeadership`). Eine Antwort läuft immer allein (Ladesperre), nach Erfolg wird das Programm neu gelesen (Kontaktperson kann wechseln). Nach 4 s erscheint ein Hinweis «Das dauert länger als sonst».
- **Polling:** Detail liest alle 30 s still nach, nur sichtbar und bei aktiver App; während einer Antwort ruht es, ein Fehler lässt den alten Stand stehen.
- **Anmeldungen:** nur lesend, für Leitung der Einheit und Kantonsadmin; sortiert offen, Ja, Nein; Rangabzeichen 24 pt.
- **Kalender:** `EKEventEditViewController` (Systemdialog ausserhalb der App, keine Rechteabfrage, kein Lesen von Kalenderdaten).

- **Monats-Überschriften (Issue #34, wie Android #128):** die Liste gruppiert nach Monat, Reihenfolge wie vom Server. Überschrift «November», «Dezember», das Jahr nur beim Jahreswechsel («Januar 2027»), die erste ohne Jahr; Tage ohne lesbare Zeit bilden einen Abschnitt ohne Überschrift. Barlow 19, Header für VoiceOver. Code `ExerciseRules.groupByMonth`.
- **Zeit gross im Detail (Issue #35, wie Android #130):** unter dem Titel zwei Zeilen mit Uhr-Symbol: Uhrzeit, darunter das Datum ausgeschrieben, neutral gefärbt (nur das Symbol trägt den Akzent). Mehrtägig «… bis …», ganztägig «Ganztägig» mit Datum. Das Jahr nur, wenn es nicht das laufende ist, bei einem Jahreswechsel bei beiden Daten. Das Datum im Kopf und die Zeile «Zeit» in der Karte entfallen. VoiceOver: ein Satz. Code `ExerciseFormat.timeDisplay`.
- **Logo der Einheit (Issue #23, wie Android #16 und #104):** oben rechts auf jeder Karte (40 pt, wächst mit der Schrift) und im Profil je Einheit (32 pt); ohne Logo «JF» oder «KF» im Kreis. `GET /api/v1/einheiten/{id}/logo`, nur mit UUID, 404 heisst ohne Logo. Auf der Karte steht der Name der Einheit im VoiceOver-Satz, im Profil Name und Bezirk. Entscheid des Auftraggebers; das Design System kennt kein Logo je Einheit. `UIImage` liest kein SVG: dann bleibt das Kürzel. Code `Components/UnitMark.swift`.
- **Antwortzeile (Issue #36, wie Android #86 und #109):** die eigene Anmeldung als Leitung zeigt das Profilbild; Erfolg gibt eine Erfolgs-Haptik, ein Fehler eine Fehler-Haptik. Scrollposition: bleibt, weil die Liste still nachlädt.

Abweichungen und Lücken:

- Das Design zeichnet keine Kennzeichnung der Einheit in der Liste und nur «Detail Eltern»; bei mehreren Einheiten gibt es sie darum nicht (offen für das Design).
- Treffpunkt/Schluss-Kacheln und Ort gibt die API nicht her; das Detail zeigt Zeit, Thema, Aufgebot und Info. «Verantwortlich» entfällt.
- Rollennamen der Kontaktperson (Hauptleitung, stellvertretende Leitung) sind eine Annahme nach dem Design-Beispiel.
- In der Liste steht «Kinder» im Umschalter der Anmeldungen wie im Design, auch wenn Teilnehmende selbst antworten.
- Die Debug-Vorschauen (`#if DEBUG`) laufen erst, wenn das Projekt `DEBUG` als Swift-Bedingung setzt (Konfiguration setzt nur `GCC_PREPROCESSOR_DEFINITIONS`).

## Profil und App-Sperre (Issue #5)

Code: `Features/Profile/` (Kopf, Liste, Datenschutz, `SignOut`, `ProfileImageResizer`) und `Features/Lock/` (`AppLockController`, `BiometricAuthenticating`, `LockStore`, `appLock()`).

- **Kein Gerätecode:** das Design nennt `.deviceOwnerAuthentication` als Fallback. Die App nutzt nur `.deviceOwnerAuthenticationWithBiometrics` (wie Android `BIOMETRIC_STRONG`); wer Face ID nicht nutzen kann, wählt «Mit Passwort anmelden» (meldet ab).
- **Biometrie geändert:** weicht der Stand der Biometrie (`LAContext.domainState`) von dem der Einrichtung ab, bleibt die Sperre zu und fragt nicht; die Person meldet sich neu an (Android: Schlüssel ungültig, Login mit Passwort). Der Zustand liegt in der Keychain (nur dieses Gerät); er gilt, bis das Abmelden ihn löscht.
- **Kamera:** «Foto aufnehmen» fehlt, es gibt nur «Foto auswählen» (`PhotosPicker`, braucht keine Berechtigung).
- **Benachrichtigungen:** Zeile führt zu `PushSettingsView` statt «Kommt bald».
- **Mehrere Einheiten:** eine Info-Zeile «Einheit · Bezirk …» je Einheit. Eltern sehen keine Einheitszeile, weil das Profil nur Einheiten mit Rolle nennt.
- **Gesperrt:** Zustand ohne Vorlage im Design; Aufbau wie `StateView` (Symbol, Titel, Satz, «Entsperren», Textknopf).
- **Datenschutz:** «Stand» zeigt die Fassung (die API liefert kein Datum).



- **Profilbild zuschneiden (Issue #22, wie Android #98):** ohne Vorlage, Wunsch des Auftraggebers. Nach der Auswahl öffnet sich `CropImageView`: Quadrat mit Kreis als Hilfslinie, Verschieben per Geste, Zoom 1- bis 4-fach per Regler oder Zwei-Finger-Geste. VoiceOver-Aktionen «Ausschnitt nach links/rechts/oben/unten». «Übernehmen» lädt JPEG mit 512 px, gedreht, ohne EXIF; «Abbrechen» lädt nichts hoch. Rechnung `ProfileImageCrop`, Encoder `ProfileImageResizer`.
- **Konto aufs Kind übertragen:** gibt es in der App nicht (Entscheid des Auftraggebers vom 13.11.2026, Issue #24 auf Android, Issue #16 hier geschlossen): Das Übertragen geschieht nur im Admin-Panel. Der Platzhalter `TransferInfoView` ist entfernt (Issue #51); es gibt keine Zeile im Profil und keinen Hinweis in der Termin-Ansicht.

## Wartung, Leiter-Plätze und Infokanal (Issues #64, #66, #68)

Alle drei sind nach dem Vertrag im Vault gebaut («FR API Vertrag Apps Nr 27-34», 13.11.2026). Das Backend hat sie noch nicht gebaut und `openapi.yaml` führt sie nicht: Der Vertragstest nimmt sie über `pendingInBackendContract` aus, bis `api-vertrag/` sie enthält. Für iOS gibt es Boards (ZN10/ZT10, PN01–PN17/PT01–PT17); sie liegen als Artifact vor und sind hier nicht gelesen, die Umsetzung folgt den Texten und den Bausteinen.

- **Wartung (Nr. 27):** 503 mit Code `WARTUNG` (bei jedem Aufruf, auch bei der Anmeldung) legt `MaintenanceView` über alles ausser die App-Sperre; der Inhalt darunter bleibt stehen. Text des Betreibers (höchstens 280 Zeichen) oder der Standardtext, mit dem Ende, wenn es eines gibt. «Erneut prüfen» ruft `GET /api/v1/wartung`, keine Dauerabfrage; danach läuft die Übungsliste neu. Ein 503 ohne diesen Code bleibt ein gewöhnlicher Fehler. Einzige Stelle, an der die App einen Servertext zeigt. **Abweichung vom Design:** Der Hinweis «Wartungsarbeiten laufen» auf Plätze-Liste und -Detail (Plätze sichtbar, Knöpfe gesperrt) ist nicht gebaut; der Vollbildschirm hat Vorrang.
- **Leiter-Plätze (Nr. 34):** `leitungPlaetze` nur bei Terminen mit Höchstzahl und nur für Kommando und Leitung. Karte: «Noch 2 Plätze frei», «Noch 1 Platz frei», «Voll», «Warteliste, Platz 2», ohne Alarmfarbe. Detail: Abschnitt «Leiter-Plätze» mit Leitenden (Profilbild, Name), «Platz frei» und Wartenden; bei «Voll» «Auf die Warteliste setzen», auf der Warteliste «Von der Warteliste nehmen», Absagen mit Platz fragt «Absagen?». `PUT …/leitung` antwortet 200 mit `status` und `position`; «ja» bei vollem Termin heisst Warteliste (kein Fehler). Rennen um den letzten Platz: Alert statt Snackbar. Nachrücken: Hinweis «Du bist nachgerückt.». Widget: nur «Voll» oder «Warteliste». Ein Server vor dieser Fassung (204, keine Schlüssel) ändert nichts.
- **Infokanal (Nr. 30):** Reiter mit Badge (Summe der ungelesenen); eine Einheit: direkt der Verlauf, mehrere: Liste. Einwegkanal: Eingabe nur bei `darfSchreiben`, Bestätigung «Geht an alle in …», Bearbeiten und Löschen nach den Rechten des Servers, nur Text, Links nur `http(s)`. Push `typ: infokanal` öffnet den Verlauf; Schalter `pushInfokanal`. **Annahmen (ohne Board gelesen):** Karten statt Sprechblasen, Tagestrenner («Heute» oder Datum), Rolle «Kommando» oder «Leitung» hinter dem Namen, Zähler ab 1800 von 2000 Zeichen.
- **Push ohne bekanntes Ziel (Nr. 29):** `typ: mitteilung` ohne `id` und jeder unbekannte `typ` öffnen nur die App.

## Erster Start (Login, Passwort, Willkommen)

Code in `FireResponse/Features/Onboarding/`, Ablauf in `App/AppModel.swift` (`phase`).

- **Flamme und Wappen** liegen nicht als Bilddatei vor und sind in `BrandArt.swift` als SwiftUI-Shapes nach den SVGs der Login-Vorschau gezeichnet (Farben fest). Ersetzen, sobald das Design Assets liefert.
- **Flamme kleiner als im Mockup** (230 statt 420 pt) und Teil des scrollenden Inhalts: Text liegt nie über Rot und Gelb (Kontrast). Der Inhalt beginnt darunter.
- **Login-Panel** nutzt `surface-container-low` (Komponenten-README) statt `surface-container` (Design-README); die Felder heben sich auf beiden ab.
- **Passwort:** zusätzlich das Feld «Startpasswort», wenn die App es nicht mehr im Arbeitsspeicher hat (App nach dem Login beendet). Fehlende Eingaben und verletzte Regeln zeigen einen Hinweis statt eines ausgegrauten Knopfs.
- **Willkommen:** «Passwort gespeichert» als Chip mit Symbol und Wort; die Einwilligung zeigt den Text von `GET /einwilligung` in einer Karte über der Häkchen-Zeile. Der Einheitsname kommt aus `einheiten`; Eltern haben keine, dann steht «Jugend- und Kinderfeuerwehr».
- **Keine Einheit** (weder Einheit noch Teilnehmende) wird vor der Einwilligung gezeigt: Ohne Einheit gibt es keine Daten, die man einwilligen könnte.
- **Globale Ladesperre:** Solange eine Aktion läuft, ist der ganze Ablauf gesperrt (`AppModel.isBusy`) und «Einen Moment …» wird angesagt.
- **Tastatur:** `FRTextField` hält seinen Fokus intern; «Weiter» springt darum nicht ins Passwortfeld.
