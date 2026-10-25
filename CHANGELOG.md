# Changelog

## Web-Erweiterung

- Browser-Oberfläche für alle acht unterstützten Editorbereiche ergänzt.
- Vorhandenen Swift-/Zstd-/CityHash-Kern als WebAssembly wiederverwendet;
  Dateiverarbeitung und Änderungen laufen in einem lokalen Web Worker.
- Original-Backup, geprüften Save-Download, Rückgängig/Wiederholen und
  abbrechbare Verarbeitung ergänzt.
- Reproduzierbaren separaten Web-Build, synthetische Integrationstests und
  GitHub-Pages-Workflow ergänzt.

## 0.4.3

- Native App, Save-Framework und Release-ZIP ausschließlich für Apple Silicon
  (`arm64`) bauen; Intel-Anteil des Downloads entfällt.
- Architekturprüfung und Release-Anleitung auf Apple Silicon umstellen.

## 0.4.2

- Ad-hoc-Distribution ohne Hardened Runtime bauen, damit das eingebettete
  Save-Framework keine nicht erfüllbare Team-ID-Validierung auslöst.
- Startprüfung der entpackten Release-App vor dem Veröffentlichen ergänzen.

## 0.4.1

- Datei- und Exportdialoge an das zugehörige Editorfenster gebunden; jeweils nur
  ein Dateidialog gleichzeitig.
- Lesen, Formatprüfung und Backup-Prüfung beim Öffnen sowie nach Speichern und
  Wiederherstellen in einen Hintergrund-Task verlegt. Die Oberfläche zeigt den
  Ladezustand an und bleibt bedienbar.
- Bisherigen Editorstand bei fehlgeschlagenem Öffnen erhalten; während des Ladens
  geänderte Quelldateien ablehnen.
- Fünf Tests für den Dateilader ergänzt, einschließlich beschädigter Dateien,
  Wiederherstellungsinformationen und unverändertem Dateizugriff.
- Eigenes App-Icon mit transparentem Außenrand und allen zehn macOS-Größen
  eingebunden.

## 0.4.0

- Vier nachgewiesene Save-Buildkennungen unterstützen und den ursprünglichen
  Header beim Schreiben beibehalten.
- Sammlungskatalog der geprüften Mac-Version 0.6.4 mit 572 IDs aus zwölf
  Tabellen ergänzen.
- Vorhandene Weltzustände einzeln bearbeiten.
- Belohnungsdefinitionen aus 99 Questpaketen anzeigen; unterstützte feste
  XP-/Geldbelohnungen beim normalen Erstabschluss gemeinsam vormerken.

Grenzen und Voraussetzungen der Bearbeitungsfunktionen stehen in der
[README](README.md). Vollständige Questskript-Automatik, Gameplay-Ladetests und
Cloud-Synchronisierungstests sind nicht Bestandteil dieses Stands.
