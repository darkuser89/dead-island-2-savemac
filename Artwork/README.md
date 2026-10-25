# App-Icon

`DeadIsland2SaveMac-icon.png` ist die Quelldatei des eigenen App-Icons:
1254 × 1254 Pixel, PNG mit transparentem Außenrand.

Die Grafik wurde für dieses Projekt mit OpenAI imagegen erstellt. Motivvorgabe:
Machete vor Palmen und einem Sonnenuntergang in Los Angeles, dunkle Metallkachel
und ein kleines Zahnrad als Hinweis auf den Save-Editor; ohne Text und offizielles
Spiellogo. Es wurde kein Icon aus einer der Spiele-Apps übernommen.

Die Grafik gehört zum Projekt und wird unter dessen
[AGPL-3.0-or-later-Lizenz](../LICENSE) bereitgestellt. Namen und Marken des Spiels
bleiben ihren jeweiligen Inhabern zugeordnet.

## Einbindung

Der Asset-Katalog liegt unter
`macOS/SaveMac/Assets.xcassets/AppIcon.appiconset`. Er enthält die macOS-Größen
16, 32, 128, 256 und 512 Punkte jeweils in 1× und 2×, insgesamt zehn PNG-Dateien.
Die Ableitungen wurden mit dem macOS-Werkzeug `sips` proportional auf die
jeweilige Pixelgröße skaliert. Transparenz und Motiv bleiben erhalten.

`project.yml` setzt `ASSETCATALOG_COMPILER_APPICON_NAME` auf `AppIcon`.
Die eingecheckte Xcode-Projektdatei enthält den Asset-Katalog als Ressource.
Xcode erzeugt beim Bauen die Icon-Ressourcen im App-Bundle; diese Buildprodukte
gehören nicht ins Repository.
