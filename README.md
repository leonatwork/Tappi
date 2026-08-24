# Tappi

Ein Fensterwechsler für macOS, der sich anfühlt wie Alt-Tab unter Windows — und zwar
**sofort**. Kein Warten, kein Ruckeln, keine CPU-Spitzen beim Drücken.

Standard-Hotkey: <kbd>⌥</kbd><kbd>Tab</kbd>.

---

## Warum

macOS' <kbd>⌘</kbd><kbd>Tab</kbd> wechselt **Apps**, nicht **Fenster**. Wer drei
Browserfenster und zwei Terminals offen hat, landet damit immer nur bei der App und muss
danach nochmal mit <kbd>⌘</kbd><kbd>`</kbd> weitersuchen. Windows wechselt seit jeher
zwischen einzelnen Fenstern — das ist der eigentliche Unterschied, an den man sich gewöhnt.

Es gibt bereits [AltTab](https://github.com/lwouis/alt-tab-macos), das dieses Verhalten
nachbildet. Der Grund für Tappi ist nicht der Funktionsumfang, sondern die Reaktionszeit.
AltTab berechnet die Fenstervorschauen **während man wartet** — das ist in dessen eigenen
Issues dokumentiert: rund 200 ms bei etwa zehn Fenstern
([#45](https://github.com/lwouis/alt-tab-macos/issues/45)), dazu Speicherprobleme durch
`replayd` ([#4194](https://github.com/lwouis/alt-tab-macos/issues/4194)) und spürbare
Verzögerungen bei vielen Fenstern ([#171](https://github.com/lwouis/alt-tab-macos/issues/171)).

Windows fühlt sich schnell an, weil der Compositor (DWM) die Fensterinhalte ohnehin schon
vorliegen hat. Der Switcher muss beim Tastendruck nichts mehr berechnen. Genau dieses
Prinzip setzt Tappi um.

## Das Windows-Verhalten, das hier nachgebaut ist

Recherchiert und Regel für Regel umgesetzt:

- Die Liste enthält **Fenster**, nicht Apps, sortiert nach zuletzt benutzt (MRU).
  Index 0 ist das aktuelle Fenster, Index 1 das davor.
- Beim Öffnen ist **Index 1 vorausgewählt**. Kurz drücken und loslassen springt daher
  direkt zum vorherigen Fenster.
- Die MRU-Reihenfolge wird **erst beim Loslassen** neu sortiert, nie während des
  Durchblätterns. Nur deshalb funktioniert das Hin-und-Her-Wechseln zwischen zwei Fenstern.
- <kbd>⇧</kbd> beim ersten Druck springt ans **Ende** der Liste.
- <kbd>Esc</kbd> bricht ab, ohne zu wechseln.
- <kbd>⌃</kbd> zusätzlich gedrückt öffnet die Liste **fixiert** — sie bleibt offen,
  auch wenn man den Modifier loslässt.
- Maus-Hover wählt aus, Klick wechselt, das „✕" auf der Kachel schließt das Fenster.

## Tastenbelegung

| Taste | Wirkung |
|---|---|
| <kbd>⌥</kbd><kbd>Tab</kbd> | Öffnen und vorwärts blättern |
| <kbd>⌥</kbd><kbd>⇧</kbd><kbd>Tab</kbd> | Rückwärts blättern |
| <kbd>⌥</kbd><kbd>`</kbd> | Nur Fenster der aktuellen App |
| <kbd>⌥</kbd><kbd>⌃</kbd><kbd>Tab</kbd> | Liste fixiert öffnen (bleibt offen) |
| Pfeiltasten | Auswahl bewegen |
| <kbd>⏎</kbd> / <kbd>Space</kbd> | Bestätigen |
| <kbd>Esc</kbd> | Abbrechen |
| <kbd>W</kbd> | Ausgewähltes Fenster schließen |
| <kbd>Q</kbd> | App des ausgewählten Fensters beenden |

Der Modifier lässt sich im Menüleisten-Menü auf <kbd>⌘</kbd> oder <kbd>⌃</kbd> umstellen.

## Geschwindigkeit

Gemessen auf macOS 26.6 (Apple Silicon) bei 12 offenen Fenstern mit aktivierten
Vorschaubildern — Zeit vom Tastendruck bis das Panel auf dem Bildschirm steht:

```
visible after 1.1 ms     visible after 1.0 ms
visible after 1.2 ms     visible after 1.7 ms
visible after 1.2 ms     visible after 1.0 ms
visible after 1.0 ms     visible after 1.2 ms
```

Nachmessen lässt sich das jederzeit mit `TAPPI_DEBUG=1` (siehe unten).

### Wie das erreicht wird

Die Regel lautet: **im Hotkey-Pfad wird nichts berechnet.**

- **Die Fensterliste ist immer warm.** Fenster, Titel, Icons und MRU-Reihenfolge werden
  laufend im Hintergrund gepflegt — angestoßen von Accessibility-Notifications, nicht vom
  Tastendruck. Beim Drücken wird ein fertiges Array gelesen.
- **Alle Accessibility-Aufrufe laufen abseits des Main Threads**, mit hartem Timeout
  (250 ms) pro App. Eine hängende App kann den Switcher damit nicht blockieren.
- **Das Panel existiert bereits.** Es wird beim Start einmal erzeugt und danach nur noch
  ein- und ausgeblendet, statt pro Aufruf neu aufgebaut zu werden.
- **Gezeichnet wird in einer einzigen `draw(_:)`-View** — keine Collection View, kein
  Auto Layout, kein SwiftUI-Diffing zwischen Tastendruck und Pixeln.
- **Vorschaubilder sind rein additiv.** Das Panel erscheint sofort mit App-Icons; die
  Live-Vorschau wird asynchron nachgeladen, in den Cache gelegt und blendet sich in die
  jeweilige Kachel ein. Gewartet wird darauf nie.

Der teuerste Einzelposten war übrigens nicht das Zeichnen, sondern
`CGPreflightScreenCaptureAccess()` — ein synchroner Aufruf an den TCC-Daemon, der pro
Sitzung 13× erfolgte und allein für 120–160 ms Verzögerung sorgte. Das Ergebnis wird jetzt
zwischengespeichert.

Im Leerlauf: rund 1 % CPU-Zeit und ~60 MB RSS.

## Installation

Voraussetzung sind die Xcode Command Line Tools (`xcode-select --install`), ein volles
Xcode wird nicht gebraucht.

```bash
./build.sh --install
```

Das baut `Tappi.app`, legt sie in `/Applications` ab und startet sie. Ohne `--install`
landet das Bundle nur in `./dist/`.

### Berechtigungen

- **Bedienungshilfen** (zwingend): Beim ersten Start erscheint der Systemdialog. Ohne
  diese Freigabe kann Tappi weder Tastendrücke sehen noch Fenster in den Vordergrund holen.
- **Bildschirmaufnahme** (optional): Nur für die Vorschaubilder. Tappi fragt **nicht**
  von sich aus danach — erst wenn man „Vorschaubilder" im Menü einschaltet. Ohne diese
  Freigabe zeigen die Kacheln App-Icons, alles andere funktioniert unverändert.

> **Hinweis zur Signatur:** `build.sh` signiert ad-hoc. macOS bindet erteilte
> Berechtigungen an die Signatur, weshalb sie nach einem Neubau eventuell erneut erteilt
> werden müssen. Wer eine Developer-ID besitzt, umgeht das mit
> `CODESIGN_IDENTITY="Developer ID Application: …" ./build.sh --install`.

## Einstellungen

Über das Menüleisten-Symbol: Modifier, Einblendeverzögerung, Kachelgröße,
Vorschaubilder, minimierte Fenster, Fenster anderer Spaces, Fenster ausgeblendeter Apps,
Auswahl-per-Maus und Autostart.

Alles liegt als JSON in `~/Library/Application Support/Tappi/settings.json` und lässt sich
auch direkt bearbeiten.

Die **Einblendeverzögerung** steht standardmäßig auf 0 ms (Windows-Verhalten). Wer beim
schnellen Hin-und-Her-Wechseln gar kein Panel sehen will, stellt sie auf 60–120 ms — dann
erscheint es nur, wenn man den Modifier tatsächlich gedrückt hält.

## Diagnose

```bash
TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi
```

Protokolliert jedes gesehene Tastenereignis samt Entscheidung, ob es geschluckt wurde,
sowie die Latenz jeder Sitzung.

## Bekannte Grenzen

- Fenster werden über die Accessibility-API erfasst. Apps mit unsauberer
  AX-Unterstützung (manche Java- und Electron-Anwendungen) melden ihre Fenster
  unvollständig.
- Der Wechsel zu einem Fenster auf einem anderen Space löst die übliche
  macOS-Space-Animation aus — daran kann Tappi nichts ändern.
- Bei <kbd>⌘</kbd> als Modifier konkurriert Tappi mit dem System-Switcher von macOS.
  <kbd>⌥</kbd> ist die konfliktfreie Voreinstellung.
- Getestet auf macOS 26.6, Apple Silicon. Minimum ist macOS 14.

## Aufbau

| Datei | Aufgabe |
|---|---|
| `WindowStore.swift` | Immer aktuelle Fensterliste samt MRU-Reihenfolge |
| `SwitcherController.swift` | Zustandsautomat einer Sitzung (die Windows-Regeln) |
| `EventTap.swift` | Tastenereignisse abfangen, bevor die App sie sieht |
| `SwitcherPanel.swift` | Das vorgehaltene Overlay-Fenster |
| `SwitcherView.swift` | Layout und Zeichnen der Kacheln |
| `ThumbnailProvider.swift` | Asynchrone Vorschaubilder via ScreenCaptureKit |
| `AX.swift` | Accessibility-Aufrufe mit Timeout-Schutz |
| `StatusItem.swift` | Menüleisten-Menü |

## Lizenz

MIT
