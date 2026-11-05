# Design

Dieses Dokument hält fest, wie die App das Design des Auftraggebers («Fire-Response iOS») umsetzt und wo sie davon abweicht. Tokens aus dem Design System gehen vor den Mockups.

## Zuordnung Baustein → Code

| Baustein | Code |
|---|---|
| Farb-Tokens (Nacht, Tag, je Mehr Kontrast) | `FireResponse/Assets.xcassets/Colors`, `Design/Colors.swift` (`Color.frSurface` …) |
| Schrift | `Design/Typography.swift`: Barlow Condensed nur für Titel (`relativeTo:`), sonst SF Pro über Textstile |
| Abstände, Grössen, Ecken | `Design/Metrics.swift`: `Spacing`, `Sizes`, `Radius` |

## Regeln

- Kein Zustand nur über Farbe: immer Symbol und Wort.
- Textpaare mindestens 4.5:1, `outline`, `focus` und `switch-on` mindestens 3:1, in allen vier Erscheinungen.
- Jedes bedienbare Element mindestens 44 × 44 pt. Keine festen Höhen für Text.
- Signalrot (`primary`) nur für die eine Hauptaktion pro Screen.
- Nur iPhone, `de-CH`, native Tab Bar und NavigationStack mit Large Titles.
