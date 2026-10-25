# Hinweise zu WebAssembly-Laufzeitkomponenten

Die Lizenztexte in diesem Ordner werden unverändert mit der gebauten Website
unter `licenses/` ausgeliefert. Zusätzlich kopiert das Buildskript die
Swift-Runtime-Lizenz direkt aus der verwendeten offiziellen Swift-Toolchain,
sowie die im Repository enthaltenen Zstd-/CityHash-Lizenzen und die MIT-Lizenz
von `@bjorn3/browser_wasi_shim` aus dem festgelegten Paket.

Quellen der ergänzenden Laufzeit-Lizenztexte:

- ICU/Unicode: `unicode-org/icu`, Tag `release-77-1`, Datei `LICENSE`.
- LLVM compiler-rt: `llvm/llvm-project`, Tag `llvmorg-21.1.0`, Datei
  `compiler-rt/LICENSE.TXT` (Apache-2.0 mit LLVM Exceptions).
- WASI-libc: `WebAssembly/wasi-libc`, Dateien `LICENSE`, `LICENSE-MIT`,
  `libc-top-half/musl/COPYRIGHT`, `libc-bottom-half/cloudlibc/LICENSE` und
  `fts/musl-fts/COPYING`.

Diese Angaben betreffen die Build-/Laufzeitabhängigkeiten. Sie ändern nicht die
AGPL-3.0-or-later-Lizenz des Editorcodes. Der gemeinsame native Save-Kern und seine
Bibliotheken werden aus den versionierten Projektquellen gebaut.
