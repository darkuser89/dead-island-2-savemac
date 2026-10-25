// SPDX-License-Identifier: AGPL-3.0-or-later
export class SaveSession {
  constructor() { this.clear(); }
  clear() {
    this.original = null; this.current = null; this.model = null;
    this.name = ''; this.undoStack = []; this.redoStack = [];
    this.backupDownloaded = false; this.exported = null;
  }
  open(name, save, model) {
    this.clear(); this.name = name; this.original = save; this.current = save; this.model = model;
  }
  apply(result) {
    if (result.save !== this.current) {
      this.undoStack.push(this.current); this.redoStack = [];
      // Bound browser history by both count and compressed byte storage.
      let size = this.undoStack.reduce((sum, item) => sum + item.length * 2, 0);
      while (this.undoStack.length > 30 || (size > 64 * 1024 * 1024 && this.undoStack.length > 1)) {
        size -= this.undoStack.shift().length * 2;
      }
    }
    this.current = result.save; this.model = result.model;
  }
  restore(result, direction) {
    const source = direction === 'undo' ? this.undoStack : this.redoStack;
    if (!source.length || source.at(-1) !== result.save) throw new Error('Der Bearbeitungsverlauf wurde inzwischen geändert.');
    const destination = direction === 'undo' ? this.redoStack : this.undoStack;
    destination.push(this.current); source.pop(); this.current = result.save; this.model = result.model;
  }
  get changed() { return this.current !== this.original; }
  get unsaved() { return this.changed && this.current !== this.exported; }
}
export function toBase64(bytes) {
  let value = '';
  for (let offset = 0; offset < bytes.length; offset += 32768) value += String.fromCharCode(...bytes.subarray(offset, offset + 32768));
  return btoa(value);
}
export function fromBase64(text) {
  return Uint8Array.from(atob(text), char => char.charCodeAt(0));
}
