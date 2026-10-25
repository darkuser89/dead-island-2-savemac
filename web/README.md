# Save Editor Web

Browser-Erweiterung des nativen Save-Managers. Der Editor lädt den gleichen
Swift-Save-Kern als WebAssembly in einen Web Worker. Zstd-Kompression, CityHash64,
Formatprüfung und Bearbeitungsregeln stammen aus den vorhandenen Quellen unter
`macOS/SaveCore`, `macOS/NativeCodec` und `macOS/ThirdParty`. Es gibt keinen
zweiten nachgebauten Save-Parser in JavaScript.

## Benutzung

1. Das Spiel vollständig beenden und die lokale `.sav`-Datei auswählen.
2. **Original sichern** wählen und den Download des unveränderten Originals
   aufbewahren. Dieses Backup ist eine normale `.sav`-Datei, kein nativer
   `.savemac-backup`-Container.
3. Charakter oder Account-Lager und einen Editorbereich auswählen.
4. Werte eingeben und **Werte übernehmen** wählen. Strukturaktionen werden direkt
   im Browser geprüft. Ungültige Aktionen verändern den bisherigen Stand nicht.
5. **Save herunterladen** wählen. Vor dem Download wird die genaue Ausgabedatei
   erneut gelesen und geprüft.
6. Den Download selbst an den vom Spiel verwendeten Speicherort kopieren und dort
   die bisherige Datei ersetzen. Das unveränderte Original-Backup behalten.

Die Web-Version überschreibt die ausgewählte Datei nicht. Sie kann weder
Mac-App-Container selbst durchsuchen noch ein laufendes Spiel erkennen oder
Dateien in iCloud beziehungsweise Steam Cloud synchronisieren. Die Auswahl
**Mac App Store / Steam** ist eine Anzeige, keine Save-Konvertierung.
Der Browser kann gleiche Downloadnamen umbenennen; beim manuellen Dateiersatz
muss der vom Spiel erwartete Dateiname wieder stimmen.

## Bearbeitungsbereiche

- **Charakter:** XP, Wut, Medkits und erkannte Geldwerte; XP maximieren.
- **Inventar:** Waffen- und Materialsammlungen, Lager, Mengen, Waffenwerte,
  Duplizieren, Entfernen, Kopieren/Verschieben und neue Gegenstände. Material-
  und Geldstapel werden auf die angegebene Menge gesetzt. Der System- und
  Referenzschutz des gemeinsamen Kerns bleibt aktiv.
- **Mods und Perks:** erkannte Listen, automatische Upgrade-Anzahl und Import
  des optionalen Upgrade-CSV-Katalogs. Die bekannte Nahkampf-/Fernkampfzuordnung
  filtert die angebotenen Upgrades.
- **Freischaltungen:** Baupläne, Curveballs und weitere bekannte IDs, eigener
  Save-Import zur Angebotserweiterung und explizite zusätzliche Tabellen-IDs.
- **Quests:** Status, Ziele, Anzeigeindizes und Checkpoint-Listen. Die begrenzte
  Standard-Erstabschlussaktion verwendet denselben XP-/Geldkatalog und dieselben
  Versions-/Doppelvergabeschranken wie die Mac-App.
- **Skillkarten:** Aufdecken, Freischalten, Kategorien und Slots, Ausrüsten,
  Ersetzen und Ablegen. Das Sperren einer Kategorie legt ihre aktiven Karten ab;
  ein belegter einzelner Slot wird erst nach dem Ablegen gesperrt.
- **Sammlungen:** derselbe Katalog mit 572 IDs aus zwölf Tabellen der geprüften
  Mac-Version 0.6.4; einzeln oder für die gefilterte Auswahl aktivieren/deaktivieren.
- **Weltzustände:** vorhandene erkannte Schalter nach Objekt-/Gebietsnamen suchen
  und einzeln umstellen. Umfangreiche Listen werden seitenweise dargestellt.
- **Erweitert:** alle erkannten numerischen Felder, einschließlich
  Rücksetzdatensätzen. Unbekannte Binärdaten bleiben geschützt.

Die vollständige Quest-zu-Welt-Automatik ist auch in der Web-Version nicht
implementiert. Die Grenzen des gemeinsamen Kerns aus der Haupt-README gelten
weiter. Ein erfolgreicher Dateitest ersetzt keinen Gameplay-Ladetest.

## Datenschutz und Browsergrenzen

Save-Dateien und importierte CSVs werden ausschließlich im Arbeitsspeicher
verarbeitet. Die Website enthält keinen Upload-Endpunkt, keine Analyse-Skripte,
keine externen CDN-Abhängigkeiten und keine dauerhafte Save-Speicherung. Zum
Start lädt sie ihren eigenen WebAssembly-Kern, Kataloge, Grafik und JavaScript.
Der erste Download des Kerns umfasst etwa 61 MB ohne HTTP-Kompression.

Der Worker besitzt keine freigegebenen Verzeichnisse und keinen Zugriff auf das
Host-Dateisystem. Der Verlauf enthält bis zu 30 Schritte und wird zusätzlich
anhand der gespeicherten Dateigrößen begrenzt. Original und aktueller Stand bleiben
während der Sitzung separat erhalten. Ein Abbruch beendet den Worker und erhält
den bisherigen Editorstand. Beim Verlassen mit noch nicht heruntergeladenen
Änderungen wird der native Browserhinweis angefordert; ob er erscheint, entscheidet
der Browser. Beim Schließen gehen die Daten dieser Sitzung verloren.

Benötigt wird ein aktueller Browser mit JavaScript, WebAssembly, Modul-Workern und
sicherem Zufallsgenerator. HTTPS oder `localhost` verwenden. Einzelne Dateien
werden auf 128 MiB und entpackte Inhalte wie im nativen Kern auf 64 MiB begrenzt.
Der Worker hat eine Zeitgrenze von 120 Sekunden pro Anfrage und sein
WebAssembly-Speicher ist auf 1 GiB begrenzt. Große Dateien können auf Geräten mit
wenig Arbeitsspeicher fehlschlagen; es werden dabei keine Originale geschrieben.

## Bauen und testen

Unter macOS mit Python 3.12 oder neuer:

```sh
export DI2_BUILD_DIR="$HOME/Library/Developer/DeadIsland2SaveMac"
python3 script/build_web.py --setup --test
node web/tests/run.mjs "$DI2_BUILD_DIR/Web/Site"
python3 -m http.server 8765 --bind 127.0.0.1 --directory "$DI2_BUILD_DIR/Web/Site"
```

Dann `http://127.0.0.1:8765` öffnen. Node wird nur für die Integrationstests benötigt.
Das Buildskript lädt bei `--setup` die offizielle Swift-6.4.0-Toolchain, das passende
Wasm-SDK und `@bjorn3/browser_wasi_shim` 0.4.2 über feste URLs und prüft ihre
SHA-256-Werte. Die Toolchain wird im Buildordner entpackt und nicht systemweit
installiert. Für spätere Builds genügt `python3 script/build_web.py` ohne Netzwerk.
Alle Downloads, Toolchains, Objekte, Testprogramme und die fertige Website liegen
außerhalb des Quellcodes im festen Buildordner unter `Web/`.

`DI2_SWIFT_TOOLCHAIN` und `DI2_WASM_SDK` können bereits vorhandene passende
Toolchain-/SDK-Wurzeln auswählen. Automatisches Setup ist für macOS ausgelegt.
Die Produktionswebsite liegt unter `Web/Site`; nur dieser Ordner wird ausgeliefert.
Die synthetischen Testdateien werden in einem eigenen Testprogramm erzeugt und
sind nicht Teil der ausgelieferten Website. Zusätzliche lokale Referenz-Saves
können als weitere Argumente an `run.mjs` übergeben werden; sie werden nur gelesen,
Änderungen bleiben im Speicher.

## GitHub Pages

`.github/workflows/web-pages.yml` baut und testet die Web-Version und veröffentlicht
nach erfolgreichem Push auf `native-swiftui-mac-editor` ausschließlich `Web/Site`.
Bei Pull Requests werden nur Build und Tests ausgeführt. Im Repository muss
**Settings → Pages → Source → GitHub Actions** aktiviert sein. Die
`github-pages`-Umgebung muss Deployments dieses Branches zulassen.

Eine eigene Domain ist nicht erforderlich. Die Projektadresse lautet bei normaler
GitHub-Pages-Konfiguration `https://darkuser89.github.io/dead-island-2-savemac/`.

## Abhängigkeiten und Lizenzen

Projektcode: [AGPL-3.0-or-later](../LICENSE). Die Originalquellen sind über den
Quellcode-Link in der Oberfläche zugänglich. Die native Zstd-/CityHash-Herkunft
steht unter [ThirdParty](../macOS/ThirdParty/README.md).

Der Browser verwendet zusätzlich
[`@bjorn3/browser_wasi_shim` 0.4.2](https://github.com/bjorn3/browser_wasi_shim)
unter der MIT-Lizenzoption. Das Buildskript übernimmt die Bibliothek samt
MIT-Lizenz aus dem festgelegten Paket in die gebaute Website. Die Swift-Laufzeit
und Foundation aus dem offiziellen SDK stehen unter
[Apache-2.0 mit Runtime Library Exception](https://www.swift.org/LICENSE.txt);
die vom SDK mitgelieferten weiteren Lizenztexte werden beim Build mit ausgeliefert.
