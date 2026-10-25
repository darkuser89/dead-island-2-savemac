// SPDX-License-Identifier: AGPL-3.0-or-later
import { WASI, File, OpenFile } from './vendor/index.js';

// No preopened directories, sockets or host filesystem handles are supplied.
export function execute(module, request) {
  const input = new TextEncoder().encode(JSON.stringify(request) + '\n');
  if (input.byteLength > 200_000_000) throw new Error('Die Anfrage ist zu groß.');
  const stdout = new File([]), stderr = new File([]);
  const wasi = new WASI(['SaveCore'], [], [
    new OpenFile(new File(input)), new OpenFile(stdout), new OpenFile(stderr),
  ]);
  try {
    const instance = new WebAssembly.Instance(module, { wasi_snapshot_preview1: wasi.wasiImport });
    const exit = wasi.start(instance);
    if (exit !== 0) throw new Error(`Der Save-Kern wurde mit Fehler ${exit} beendet.`);
    const result = JSON.parse(new TextDecoder().decode(stdout.data));
    if (!result.ok) throw new Error(result.error || 'Der Spielstand konnte nicht verarbeitet werden.');
    return result;
  } catch (error) {
    const detail = new TextDecoder().decode(stderr.data).trim().slice(0, 300);
    if (error instanceof WebAssembly.RuntimeError) {
      throw new Error('Der Save-Kern konnte diese Datei nicht verarbeiten (Speicher- oder Laufzeitgrenze).');
    }
    throw new Error(error.message || detail || 'Fehler im Save-Kern.');
  }
}
