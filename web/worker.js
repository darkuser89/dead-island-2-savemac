// SPDX-License-Identifier: AGPL-3.0-or-later
import { execute } from './engine.js';
let module;
self.onmessage = async ({ data }) => {
  try {
    if (!module) {
      const response = await fetch(new URL('./SaveCore.wasm', import.meta.url));
      if (!response.ok) throw new Error('Der Save-Kern konnte nicht geladen werden.');
      module = await WebAssembly.compile(await response.arrayBuffer());
    }
    const result = data.request ? execute(module, data.request) : { ready: true };
    self.postMessage({ id: data.id, result });
  } catch (error) {
    self.postMessage({ id: data.id, error: error.message });
  }
};
