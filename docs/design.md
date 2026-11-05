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
