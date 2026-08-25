# Changelog

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
die Versionierung an [Semantic Versioning](https://semver.org/lang/de/).

## [1.0.0] — 2026-08-25

Erste Veröffentlichung.

### Enthalten

- Fensterwechsel nach dem Vorbild von Windows Alt-Tab: zwischen **Fenstern** statt Apps,
  in MRU-Reihenfolge, mit vorausgewähltem Index 1 — kurzes Drücken wechselt also zum
  zuletzt genutzten Fenster.
- Neusortierung erst beim Loslassen, wodurch das Hin- und Herwechseln zwischen zwei
  Fenstern funktioniert.
- <kbd>⌘</kbd><kbd>Tab</kbd> als Voreinstellung; der System-Switcher wird übernommen,
  solange Tappi arbeitsfähig ist, und andernfalls sofort zurückgegeben.
- <kbd>⌘</kbd><kbd>^</kbd> für Fenster der aktuellen App (ISO- und ANSI-Layouts).
- <kbd>⇧</kbd> rückwärts, Pfeiltasten, <kbd>Esc</kbd> zum Abbrechen,
  <kbd>⌃</kbd> für eine fixierte Liste, Maussteuerung samt „✕" zum Schließen.
- Live-Vorschaubilder via ScreenCaptureKit, asynchron nachgeladen — das Panel wartet nie
  auf sie.
- Menüleisten-Einstellungen: Modifier, Einblendeverzögerung, Kachelgröße, Vorschaubilder,
  minimierte Fenster, andere Spaces, ausgeblendete Apps, Maus-Auswahl, Autostart.
- Diagnoseprotokoll und Einzelinstanz-Schutz.

### Geschwindigkeit

1,0–1,7 ms vom Tastendruck bis zum sichtbaren Panel bei 12 Fenstern mit aktiven
Vorschaubildern; rund 0,6 % CPU-Zeit im Leerlauf.
