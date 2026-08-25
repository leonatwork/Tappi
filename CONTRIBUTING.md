# Mitwirken an Tappi

Danke für dein Interesse. Tappi ist ein kleines, fokussiertes Projekt — dieser Leitfaden
sollte reichen, um in wenigen Minuten produktiv zu sein.

## Entwicklungsumgebung

Es wird **kein Xcode** benötigt, die Command Line Tools genügen:

```bash
xcode-select --install
```

Voraussetzungen: macOS 14 oder neuer, Swift 5.9+.

```bash
git clone https://github.com/leonatwork/Tappi.git
cd Tappi
./setup-signing.sh     # einmalig, siehe unten — unbedingt vor dem ersten Build
./build.sh --install
```

### Warum `setup-signing.sh` nicht optional ist

macOS bindet erteilte Berechtigungen an die Codesignatur. Ad-hoc signierte Apps werden
über den Hash ihrer Binary identifiziert, weshalb **jeder Neubau die erteilten
Bedienungshilfen- und Bildschirmaufnahme-Rechte entwertet** — das Häkchen bleibt in den
Systemeinstellungen sichtbar, greift aber ins Leere, und Tappi meldet „Bedienungshilfen
fehlen", obwohl alles richtig aussieht.

```
ad-hoc        designated => cdhash H"..."               ← ändert sich bei jedem Build
Zertifikat    designated => certificate leaf = H"..."   ← bleibt stabil
```

`setup-signing.sh` legt dafür eine lokale, selbstsignierte Identität im Login-Schlüsselbund
an. Ein Admin-Passwort ist nicht nötig. Ohne diesen Schritt wirst du beim Entwickeln nach
jedem Build neu freigeben — das kostet mehr Zeit als das Lesen dieses Abschnitts.

## Das eine Designprinzip

**Im Hotkey-Pfad wird nichts berechnet.**

Tappi existiert, weil vergleichbare Werkzeuge ihre Fenstervorschauen berechnen, *während
der Nutzer wartet*. Alles, was zwischen Tastendruck und sichtbarem Panel liegt, ist
deshalb tabu für Arbeit, die auch vorher oder nachher erledigt werden kann:

- Die Fensterliste wird laufend im Hintergrund gepflegt (`WindowStore`), angestoßen von
  Accessibility-Notifications — nicht vom Tastendruck.
- Accessibility-Aufrufe laufen **nie** auf dem Main Thread und immer mit Timeout. Eine
  hängende Fremd-App darf den Switcher nicht blockieren.
- Das Panel wird beim Start einmal erzeugt und danach nur ein- und ausgeblendet.
- Vorschaubilder sind rein additiv: Das Panel erscheint sofort mit App-Symbolen, Vorschauen
  blenden sich asynchron ein. Es wird nie auf sie gewartet.

Als Richtwert: Vom Tastendruck bis zum sichtbaren Panel liegen 1–2 ms bei einem Dutzend
Fenstern. Wer etwas in diesen Pfad einbaut, sollte vorher und nachher messen:

```bash
TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi
```

Das protokolliert jedes Tastenereignis samt Schluck-Entscheidung sowie die Latenz jeder
Sitzung (`visible after … ms`). Ein realer Fund aus der Entwicklung: ein einzelner
`CGPreflightScreenCaptureAccess()`-Aufruf pro Fenster kostete 120–160 ms.

## Wo was liegt

| Datei | Aufgabe |
|---|---|
| `WindowStore.swift` | Immer aktuelle Fensterliste samt MRU-Reihenfolge |
| `SwitcherController.swift` | Zustandsautomat einer Sitzung (die Windows-Regeln) |
| `EventTap.swift` | Tastenereignisse abfangen, bevor die App sie sieht |
| `SwitcherPanel.swift` | Das vorgehaltene Overlay-Fenster |
| `SwitcherView.swift` | Layout und Zeichnen der Kacheln |
| `ThumbnailProvider.swift` | Asynchrone Vorschaubilder via ScreenCaptureKit |
| `SystemSwitcher.swift` | Übernahme von ⌘Tab samt Rückgabe-Sicherung |
| `AX.swift` | Accessibility-Aufrufe mit Timeout-Schutz |
| `Diagnostics.swift` | Startprotokoll für ein Programm ohne Konsole |
| `StatusItem.swift` | Menüleisten-Menü |

## Fallstricke, die schon einmal Zeit gekostet haben

- **Tastatur-Layouts.** Die Taste über Tab meldet unterschiedliche Keycodes: ANSI liefert
  50, ISO (deutsch) liefert dort 10 und legt 50 auf `<`. Wer Tastenkürzel testet, muss den
  Keycode prüfen, den die *physische Taste* sendet — ein synthetisches Ereignis mit dem
  Keycode, den der eigene Code erwartet, testet gar nichts.
- **Geflippte Views.** `SwitcherView` rechnet bewusst in AppKit-Koordinaten von unten
  links. Ein `isFlipped = true` macht das Grid-Layout lesbarer, spiegelt aber jedes
  gezeichnete Bild vertikal.
- **⌘Tab ist kein normales Tastenkürzel.** Der Window Server behandelt es als *Symbolic
  Hot Key*, bevor irgendein Event Tap es sieht. Es abzufangen genügt nicht; der Hot Key
  muss deaktiviert werden. Wer daran arbeitet, muss sicherstellen, dass er **immer**
  zurückgegeben wird — sonst bleibt der Rechner ohne jeden Fensterwechsler zurück.
- **Aus dem Terminal gestartet** erbt Tappi die Berechtigungen des Terminals. Für einen
  ehrlichen Berechtigungstest die App normal starten und ins Diagnoseprotokoll schauen.

## Pull Requests

- Ein Thema pro PR.
- Beschreibe, **warum** die Änderung nötig ist, nicht nur was sie tut. Das gilt auch für
  Kommentare im Code: Der Code sagt, was passiert; Kommentare sollen erklären, warum es so
  und nicht anders gemacht wird.
- Änderungen am Hotkey-Pfad bitte mit Messwerten (vorher/nachher) belegen.
- Der Build muss warnungsfrei durchlaufen: `swift build -c release`.
- Bitte beschreibe, wie du getestet hast — Tappi hat viele Zustände, die sich nur manuell
  prüfen lassen (mehrere Spaces, minimierte Fenster, mehrere Monitore, fehlende
  Berechtigungen).

## Fehler melden

Bitte lege das Diagnoseprotokoll bei (Menüleisten-Symbol ▸ *Diagnoseprotokoll öffnen*,
oder `~/Library/Application Support/Tappi/diagnostics.log`) sowie deine macOS-Version und
ob du Apple Silicon oder Intel nutzt. Es enthält keine Fenstertitel oder sonstigen Inhalte
— nur Startzustand und Berechtigungen.
