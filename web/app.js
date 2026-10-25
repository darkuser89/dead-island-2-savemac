// SPDX-License-Identifier: AGPL-3.0-or-later
import { SaveSession, toBase64, fromBase64 } from './session.js';

const $ = id => document.getElementById(id);
const session = new SaveSession();
const sections = ['Charakter', 'Inventar', 'Freischaltungen', 'Quests', 'Skillkarten', 'Sammlungen', 'Weltzustände', 'Erweitert'];
const ui = { section: sections[0], profile: '', collection: '', item: '', quest: '', table: '', skillCategory: '', query: '', page: 0, system: false, dlc: false };
const drafts = new Map();
let catalog = [], upgrades = [], known = [], rewards, worker, pending, requestID = 0;

function h(tag, attributes = {}, ...children) {
  const node = document.createElement(tag);
  for (const child of children.flat(Infinity)) if (child !== null && child !== undefined) node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  for (const [key, value] of Object.entries(attributes)) {
    if (key.startsWith('on')) node.addEventListener(key.slice(2).toLowerCase(), value);
    else if (key === 'class') node.className = value;
    else if (key in node) node[key] = value;
    else node.setAttribute(key, value);
  }
  return node;
}
const button = (text, action, options = {}) => h('button', { type: 'button', onclick: action, ...options }, text);
const note = text => h('p', { class: 'notice' }, text);
const muted = text => h('p', { class: 'muted small' }, text);
const option = (value, label = value) => h('option', { value }, label);
function select(values, value, change, label) {
  return h('select', { value, onchange: event => change(event.target.value), ...(label ? { 'aria-label': label } : {}) }, values.map(entry => Array.isArray(entry) ? option(...entry) : option(entry)));
}
function error(error) { $('error').textContent = error.message || String(error); $('error').hidden = false; }
function clearError() { $('error').hidden = true; }
function matches(...parts) { return parts.join(' ').toLocaleLowerCase().includes(ui.query.toLocaleLowerCase()); }
function profileItems(key) { return session.model[key].filter(item => item.section === ui.profile); }
function startWorker() {
  worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
  worker.onmessage = ({ data }) => {
    if (!pending || pending.id !== data.id) return;
    const task = pending; pending = null; clearTimeout(task.timeout); $('busy').close();
    data.error ? task.reject(new Error(data.error)) : task.resolve(data.result);
  };
  worker.onerror = event => cancel(new Error(event.message || 'Der Browser konnte den Save-Kern nicht starten.'));
}
function cancel(reason = new Error('Vorgang abgebrochen. Dein bisheriger Editorstand bleibt erhalten.')) {
  worker?.terminate(); worker = null;
  if (pending) { clearTimeout(pending.timeout); pending.reject(reason); pending = null; }
  $('busy').close();
}
async function run(request, label = 'Spielstand wird gelesen und geprüft …') {
  if (pending) throw new Error('Bitte den laufenden Vorgang abwarten.');
  clearError(); if (!worker) startWorker();
  $('busy-label').textContent = label; $('busy').showModal();
  return new Promise((resolve, reject) => {
    const id = ++requestID;
    pending = { id, resolve, reject, timeout: setTimeout(() => cancel(new Error('Der Vorgang hat die Zeitgrenze erreicht. Die Datei wurde nicht verändert.')), 120000) };
    worker.postMessage({ id, request });
  });
}
async function mutate(action, label = 'Änderung wird geprüft …') {
  try {
    if (drafts.size && action.type !== 'fields') throw new Error('Bitte zuerst die eingegebenen Werte übernehmen oder mit „Zurücksetzen“ verwerfen.');
    const result = await run({ save: session.current, action, ...(action.type === 'reward' ? { rewardCatalog: rewards } : {}) }, label);
    session.apply(result); drafts.clear(); render();
    $('status').textContent = 'Änderung geprüft. Zum Übernehmen ins Spiel den Save herunterladen und selbst ersetzen.';
    return true;
  } catch (cause) { error(cause); renderContent(); updateButtons(); return false; }
}
async function applyDrafts() {
  if (!drafts.size) return true;
  return mutate({ type: 'fields', values: Object.fromEntries(drafts) });
}
function download(save, name) {
  const url = URL.createObjectURL(new Blob([fromBase64(save)], { type: 'application/octet-stream' }));
  const anchor = h('a', { href: url, download: name });
  document.body.append(anchor); anchor.click(); anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}
function backup() {
  if (!session.original) return;
  download(session.original, session.name.replace(/\.sav$/i, '') + '-Original-Backup.sav');
  session.backupDownloaded = true; updateButtons();
  $('status').textContent = 'Download des unveränderten Originals gestartet. Bewahre diese Backup-Datei auf.';
}
async function exportSave() {
  if (!(await applyDrafts())) return;
  if (!session.backupDownloaded) { error(new Error('Bitte zuerst „Original sichern“ wählen. Danach kannst du den bearbeiteten Save herunterladen.')); return; }
  try {
    // Final verification runs on precisely the bytes that are downloaded.
    await run({ save: session.current }, 'Download wird abschließend geprüft …');
    download(session.current, session.name);
    session.exported = session.current; updateButtons();
    $('status').textContent = 'Save-Download gestartet. Im beendeten Spiel die lokale Datei selbst ersetzen. Cloud-Abgleich erfolgt durch das Spiel.';
  } catch (cause) { error(cause); }
}
async function openFile(file) {
  if (!file) return;
  if ((session.unsaved || drafts.size) && !confirm('Die bisherigen Änderungen wurden noch nicht heruntergeladen. Trotzdem einen anderen Save öffnen?')) return;
  try {
    if (file.size > 128 * 1024 * 1024) throw new Error('Der Save überschreitet die unterstützte Dateigröße.');
    const save = toBase64(new Uint8Array(await file.arrayBuffer()));
    const result = await run({ save });
    session.open(file.name, save, result.model); drafts.clear();
    ui.profile = result.model.profiles.find(item => item.id !== 'Account')?.id || result.model.profiles[0]?.id || '';
    ui.collection = ''; ui.item = ''; ui.quest = ''; ui.page = 0; ui.query = ''; $('search').value = '';
    $('platform').value = 'unknown'; render();
  } catch (cause) { error(cause); }
}
async function history(direction) {
  if (drafts.size) { error(new Error('Bitte zuerst die Werte übernehmen oder verwerfen.')); return; }
  const stack = direction === 'undo' ? session.undoStack : session.redoStack;
  if (!stack.length) return;
  try { const result = await run({ save: stack.at(-1) }); session.restore(result, direction); render(); } catch (cause) { error(cause); }
}
function updateButtons() {
  const opened = !!session.model;
  $('backup').disabled = !opened; $('download').disabled = !opened;
  $('undo').disabled = !session.undoStack.length || drafts.size > 0;
  $('redo').disabled = !session.redoStack.length || drafts.size > 0;
  $('reset').disabled = !session.changed && !drafts.size;
  $('apply').disabled = !drafts.size;
  $('apply').textContent = drafts.size ? `Werte übernehmen (${drafts.size})` : 'Werte übernehmen';
}
function fieldView(field) {
  const id = 'field-' + field.id;
  const value = drafts.get(String(field.id)) ?? field.value;
  const change = event => {
    const key = String(field.id), value = event.target.value;
    value === field.value ? drafts.delete(key) : drafts.set(key, value);
    updateButtons();
  };
  const input = field.choices.length
    ? select(field.choices, value, next => change({ target: { value: next } }), field.title)
    : h('input', { id, value, type: 'text', disabled: field.readOnly, inputMode: 'text', oninput: change, 'aria-label': field.title });
  input.id = id;
  return h('div', { class: 'field' }, h('label', { htmlFor: id }, field.title), input,
    h('small', {}, field.context || field.property, field.readOnly ? ' · automatisch verwaltet' : ''));
}
function fieldsView(fields) {
  return fields.length ? h('div', { class: 'grid' }, fields.map(fieldView)) : muted('Keine passenden bearbeitbaren Werte vorhanden.');
}
function pagination(items, renderItem, size = 70) {
  const pages = Math.max(1, Math.ceil(items.length / size));
  ui.page = Math.min(ui.page, pages - 1);
  $('count').textContent = `${items.length} Einträge`;
  return h('div', {}, items.slice(ui.page * size, (ui.page + 1) * size).map(renderItem),
    pages > 1 ? h('div', { class: 'pagination' }, button('←', () => { ui.page--; renderContent(); }, { disabled: ui.page === 0, 'aria-label': 'Vorherige Seite' }),
      `${ui.page + 1} / ${pages}`, button('→', () => { ui.page++; renderContent(); }, { disabled: ui.page + 1 === pages, 'aria-label': 'Nächste Seite' })) : null);
}
function characterView() {
  const fields = profileItems('fields').filter(field => !field.advanced && (['XPValue', 'CurrentFury', 'MedkitCount'].includes(field.property) || field.context === 'Geld')).filter(field => matches(field.title, field.context));
  const xp = fields.find(field => field.property === 'XPValue');
  return h('div', {}, note('Werte werden zunächst im Browser geändert. Deine Quelldatei bleibt beim Bearbeiten unverändert.'),
    h('div', { class: 'card' }, h('h2', {}, 'Charakterwerte'), fieldsView(fields),
      h('div', { class: 'actions' }, xp ? button('XP maximieren', () => { drafts.set(String(xp.id), '1073741824'); renderContent(); updateButtons(); }) : null,
        button('Geld hinzufügen / setzen', () => { ui.section = 'Inventar'; render(); }))),
    muted('Für Waffenwerte das Inventar öffnen. Alle weiteren erkannten Werte stehen unter „Erweitert“.'));
}
function itemDefinition(entry, collection) {
  return { name: entry.title, category: collection.itemType === 'InventoryItemInstanced' ? 'Weapons' : 'Other', archetype: entry.archetype,
    instanced: collection.itemType === 'InventoryItemInstanced', maximumCount: 999999999, dlc: false, internalItem: entry.system };
}
function inventoryView() {
  const collections = session.model.inventories.filter(item => item.section === ui.profile || item.section === 'Account');
  let collection = collections.find(item => item.id === ui.collection) || collections.find(item => item.section === ui.profile) || collections[0];
  if (!collection) return muted('Kein unterstütztes Inventar vorhanden.');
  ui.collection = collection.id;
  const entries = collection.entries.filter(item => (ui.system || !item.system) && matches(item.title, item.archetype));
  let selected = entries.find(item => item.id === ui.item) || entries[0]; ui.item = selected?.id || '';
  const list = pagination(entries, item => button(h('span', {}, item.title, item.system ? h('small', {}, 'Systemgegenstand') : null), () => { ui.item = item.id; renderContent(); }, { class: selected?.id === item.id ? 'selected' : '' }), 70);
  const detail = selected ? itemDetail(selected, collection, collections) : muted('Keine passenden Gegenstände.');
  return h('div', {}, h('div', { class: 'actions' }, select(collections.map(item => [item.id, `${item.section === 'Account' ? 'Account' : 'Charakter'} · ${item.title} (${item.entries.length})`]), collection.id, value => { ui.collection = value; ui.item = ''; ui.page = 0; renderContent(); }, 'Inventarsammlung'),
      h('label', {}, h('input', { type: 'checkbox', checked: ui.system, onchange: event => { ui.system = event.target.checked; renderContent(); } }), ' Systemgegenstände')),
    h('div', { class: 'split' }, h('div', { class: 'list' }, list), h('div', {}, detail)),
    addItemsView(collection));
}
function itemDetail(item, collection, collections) {
  const fields = item.fields.map(id => session.model.fields.find(field => field.id === id)).filter(Boolean);
  const destinations = collections.filter(target => target.itemType === collection.itemType && target.role !== 'Lost and Found');
  let destination = destinations.find(target => target.id !== collection.id)?.id || collection.id;
  const paths = item.upgrades ? [...item.upgrades] : null;
  const compatible = upgrades.filter(upgrade => upgrade.weaponType === 'any' ||
    (upgrade.weaponType === 'melee' && /\.DA_MeleeWeaponArchetype_/.test(item.archetype)) ||
    (upgrade.weaponType === 'ranged' && /\.DA_RangedWeaponArchetype_/.test(item.archetype)));
  const operation = (operation, extra = {}) => mutate({ type: 'inventory', operation, source: collection.id, item: item.id, ...extra });
  const removable = !item.system && !item.currency;
  const upgradesView = paths && !item.system ? h('details', {}, h('summary', {}, `Mods und Perks (${paths.length})`),
    paths.map(path => h('div', { class: 'row' }, h('span', { class: 'path' }, path), button('Entfernen', () => operation('upgrades', { paths: paths.filter(value => value !== path) })))),
    compatible.length ? (() => {
      let selected = compatible[0].archetype;
      return h('div', { class: 'actions' }, select(compatible.map(upgrade => [upgrade.archetype, upgrade.name]), selected, value => { selected = value; }, 'Mod oder Perk'),
        button('Hinzufügen', () => operation('upgrades', { paths: [...new Set([...paths, selected])] })));
    })() : muted('Upgrade-CSV importieren, um weitere Mods und Perks anzubieten.'),
    h('details', {}, h('summary', {}, 'Upgrade-Pfade bearbeiten'), (() => {
      const input = h('textarea', { value: paths.join('\n'), 'aria-label': 'Upgrade-Pfade, einer pro Zeile' });
      return h('div', {}, input, button('Pfade übernehmen', () => operation('upgrades', { paths: input.value.split('\n').map(value => value.trim()).filter(Boolean) })));
    })())) : muted(item.system ? 'Interner Systemgegenstand.' : paths === null && collection.itemType === 'InventoryItemInstanced' ? 'Dieses Upgrade-Format wird nicht unterstützt.' : '');
  return h('article', { class: 'card' }, h('h2', {}, item.title), h('p', { class: 'path' }, item.archetype),
    h('div', { class: 'actions' }, button('Duplizieren', () => operation('copy', { destination: collection.id }), { disabled: !removable || collection.role === 'Lost and Found' }),
      select(destinations.map(target => [target.id, target.title + (target.section === 'Account' ? ' · Account' : ' · ' + target.section.slice(0, 8))]), destination, value => { destination = value; }, 'Zielinventar'),
      button('Kopieren', () => operation('copy', { destination }), { disabled: !removable }),
      button('Verschieben', () => operation('move', { destination }), { disabled: !removable }),
      button('Entfernen', () => operation('remove'), { disabled: !removable, class: 'danger' })),
    fieldsView(fields), upgradesView);
}
function addItemsView(collection) {
  const map = new Map();
  for (const group of session.model.inventories) for (const entry of group.entries) if (!entry.system) map.set(entry.archetype, itemDefinition(entry, group));
  for (const item of catalog) map.set(item.archetype, item);
  const cash = { name: 'Geld', category: 'Special', archetype: '/Game/DI2/Items/Special/DA_InventoryTypes_Special_CashItem.DA_InventoryTypes_Special_CashItem', instanced: false, maximumCount: 999999999, dlc: false, internalItem: false };
  map.set(cash.archetype, cash);
  const definitions = [...map.values()].filter(item => !item.internalItem && (ui.dlc || !item.dlc) && item.instanced === (collection.itemType === 'InventoryItemInstanced') && (collection.section !== 'Account' || item.archetype !== cash.archetype));
  const categoryValues = [...new Set(definitions.map(item => item.category))].sort();
  const categorySelect = select([['', 'Alle Kategorien'], ...categoryValues], '', () => updateItems(), 'Gegenstandskategorie');
  const search = h('input', { type: 'search', placeholder: 'Gegenstand suchen …', 'aria-label': 'Katalog durchsuchen', oninput: () => updateItems() });
  const itemSelect = h('select', { 'aria-label': 'Neuer Gegenstand' });
  let available = [];
  function updateItems() {
    available = definitions.filter(item => (!categorySelect.value || item.category === categorySelect.value) && (item.name + item.archetype).toLowerCase().includes(search.value.toLowerCase()));
    itemSelect.replaceChildren(...available.map(item => option(item.archetype, `${item.name}${item.dlc ? ' · DLC' : ''}`)));
  }
  updateItems();
  const count = h('input', { type: 'number', min: 1, max: 999999999, value: '1', 'aria-label': 'Menge oder Geldbetrag' });
  const level = h('input', { type: 'number', min: 1, max: 99, value: '1', 'aria-label': 'Waffenlevel' });
  const rarity = select(['Common', 'Uncommon', 'Rare', 'Superior', 'Legendary'], 'Common', () => {}, 'Seltenheit');
  const seed = h('input', { type: 'number', min: -2147483648, max: 2147483647, value: '0', 'aria-label': 'Waffen-Seed' });
  const add = all => {
    const items = all ? available : available.filter(item => item.archetype === itemSelect.value);
    if (!items.length) { error(new Error('Bitte einen Gegenstand auswählen.')); return; }
    mutate({ type: 'add', definitions: items, destination: collection.id, count: Number(count.value), level: Number(level.value), rarity: rarity.value, seed: Number(seed.value) });
  };
  return h('details', { class: 'card' }, h('summary', {}, 'Gegenstände hinzufügen / Geld setzen'),
    note('Katalogeinträge erteilen keine DLC-Lizenz. Bei vorhandenen Material- und Geldstapeln wird die angegebene Menge gesetzt.'),
    h('div', { class: 'actions' }, categorySelect, search, itemSelect),
    h('div', { class: 'settings-grid' }, h('label', { class: 'stack' }, 'Menge / Betrag', count), h('label', { class: 'stack' }, 'Waffenlevel', level), h('label', { class: 'stack' }, 'Seltenheit', rarity), h('label', { class: 'stack' }, 'Seed', seed)),
    h('div', { class: 'actions' }, button('Hinzufügen / setzen', () => add(false)), button('Alle gefilterten hinzufügen', () => add(true)),
      h('label', {}, h('input', { type: 'checkbox', checked: ui.dlc, onchange: event => { ui.dlc = event.target.checked; renderContent(); } }), ' DLC-Einträge anzeigen')),
    catalogTools());
}
function catalogTools() {
  return h('div', { class: 'actions' }, button(`Gegenstands-CSV importieren (${catalog.length})`, () => $('items-input').click()), button(`Upgrade-CSV importieren (${upgrades.length})`, () => $('upgrades-input').click()));
}
function mergeTables(tables) {
  const map = new Map();
  for (const table of tables) { if (!map.has(table.name)) map.set(table.name, new Set()); for (const row of table.rows) map.get(table.name).add(row); }
  return [...map].map(([name, rows]) => ({ name, rows: [...rows].sort() })).sort((a, b) => a.name.localeCompare(b.name));
}
function unlockView(collections) {
  const all = mergeTables([...known, ...Object.values(session.model.unlocks).flat()]);
  const tables = all.filter(table => /^DT_GameEntitlement_(Journal|FuseRooms|Keys|KeyCards)(_|$)/.test(table.name) === collections);
  if (!tables.length) return muted('Keine passenden Freischaltungstabellen bekannt.');
  const table = tables.find(table => table.name === ui.table) || tables[0]; ui.table = table.name;
  const rows = table.rows.filter(row => matches(row, table.name));
  const current = new Set((session.model.unlocks[ui.profile] || []).find(entry => entry.name === table.name)?.rows || []);
  const set = values => mutate({ type: 'unlocks', section: ui.profile, tables: [{ name: table.name, rows: [...values].sort() }] });
  return h('div', {}, collections ? note('572 Sammlungseinträge aus zwölf Tabellen der Mac-Version 0.6.4. Diese Listen ändern keine Weltobjekte oder statistischen Zähler.') : note('Baupläne, Curveballs und weitere bekannte Freischaltungen. Importierte IDs werden erst durch deine Auswahl aktiviert.'),
    h('div', { class: 'actions' }, select(tables.map(entry => [entry.name, entry.name.replace('DT_GameEntitlement_', '') + ` (${entry.rows.length})`]), table.name, value => { ui.table = value; ui.page = 0; renderContent(); }, 'Freischaltungstabelle'),
      button('Angezeigte aktivieren', () => set(new Set([...current, ...rows]))), button('Angezeigte deaktivieren', () => set(new Set([...current].filter(row => !rows.includes(row))))),
      button('IDs aus eigenem Save einlesen', () => $('unlocks-input').click())),
    h('div', { class: 'card' }, pagination(rows, row => h('div', { class: 'row' }, h('label', {}, h('input', { type: 'checkbox', checked: current.has(row), onchange: event => { const values = new Set(current); event.target.checked ? values.add(row) : values.delete(row); set(values); } }), row)))),
    h('details', { class: 'card' }, h('summary', {}, 'Zusätzliche ID eintragen'), (() => { const input = h('input', { type: 'text', placeholder: 'Exakte bekannte Tabellen-ID', 'aria-label': 'Zusätzliche Tabellen-ID' }); return h('div', { class: 'actions' }, input, button('Aktivieren', () => set(new Set([...current, input.value.trim()])))); })()));
}
function questsView() {
  const quests = profileItems('quests').filter(quest => matches(quest.title, quest.key));
  const quest = quests.find(item => item.id === ui.quest) || quests[0]; ui.quest = quest?.id || '';
  if (!quest) return muted('Keine passenden Quests vorhanden.');
  const stateSelect = (current, id, type) => select(type === 'quest' ? ['Waiting', 'Started', 'Complete'] : ['Waiting', 'Started', 'Stopped', 'Complete'], current,
    state => mutate({ type, id, state, ...(type === 'quest' ? { includeObjectives: false } : {}) }), 'Status');
  const indexField = entry => {
    const input = h('input', { type: 'number', min: 0, max: 1000000, value: entry.index, 'aria-label': 'Anzeigeindex' });
    return h('div', { class: 'actions' }, input, button('Anzeigeindex setzen', () => mutate({ type: 'displayIndex', id: entry.id, index: Number(input.value) })));
  };
  const rule = rewards?.definitions.find(rule => rule.id.toLowerCase() === quest.key.toLowerCase());
  const supportsReward = session.model.version === '0x0012fee2' && rule && !rule.other.length && (rule.xp > 0 || rule.cash > 0) && quest.state !== 'Complete';
  return h('div', {}, note('Statusänderungen führen keine Questskripte aus. Weltzustände, Erfolge und unbekannte Lootbelohnungen werden nicht automatisch ergänzt.'),
    h('div', { class: 'split' }, h('div', { class: 'list' }, pagination(quests, item => button(h('span', {}, item.title, h('small', {}, item.state)), () => { ui.quest = item.id; renderContent(); }, { class: quest.id === item.id ? 'selected' : '' }))),
      h('article', { class: 'card' }, h('h2', {}, quest.title), stateSelect(quest.state, quest.id, 'quest'), indexField(quest),
        h('div', { class: 'actions' }, button('Mit allen Zielen abschließen', () => mutate({ type: 'quest', id: quest.id, state: 'Complete', includeObjectives: true })),
          button('Quest zurücksetzen', () => mutate({ type: 'quest', id: quest.id, state: 'Waiting', includeObjectives: true }))),
        rule ? h('div', { class: 'card' }, h('h3', {}, 'Standardbelohnung'), muted(`${rule.xp} XP · ${rule.cash} Geld${rule.other.length ? ' · zusätzliche Typen: ' + rule.other.join(', ') : ''}`),
          button('Normalen Erstabschluss mit XP/Geld anwenden', () => { if (confirm('Dies ist ein normaler Erstabschluss ohne New Game Plus? Die Aktion schreibt ausschließlich unterstützte feste XP-/Geldwerte und Questziele.')) mutate({ type: 'reward', id: quest.id, confirmed: true }); }, { disabled: !supportsReward })) : muted('Keine passende Standardbelohnung im Katalog.'),
        h('h3', {}, `Questziele (${quest.objectives.length})`), quest.objectives.map(objective => h('details', {}, h('summary', {}, objective.title), stateSelect(objective.state, objective.id, 'objective'), indexField(objective))),
        h('h3', {}, 'Checkpoint-Ziele'), quest.checkpoints.map(checkpoint => {
          const input = h('textarea', { value: checkpoint.completed.join('\n'), 'aria-label': 'Abgeschlossene Checkpoint-Ziele, eines pro Zeile' });
          return h('details', {}, h('summary', {}, checkpoint.key), input, button('Checkpoint übernehmen', () => mutate({ type: 'checkpoint', id: checkpoint.id, completed: input.value.split('\n').map(value => value.trim()).filter(Boolean) })));
        }))));
}
function skillsView() {
  const state = session.model.skills[ui.profile];
  if (!state) return muted('Keine unterstützten Skillkarten-Daten vorhanden.');
  const category = state.categories.find(entry => entry.path === ui.skillCategory) || state.categories[0];
  ui.skillCategory = category?.path || '';
  const act = (operation, values) => mutate({ type: 'skill', operation, section: ui.profile, ...values });
  const cards = state.cards.filter(card => matches(card.title, card.path));
  const categories = h('details', { class: 'card' }, h('summary', {}, 'Kategorien und Slots'), state.categories.map(category => h('div', {},
    h('div', { class: 'row' }, h('label', {}, h('input', { type: 'checkbox', checked: category.unlocked, onchange: event => act('category', { category: category.path, enabled: event.target.checked }) }), category.title)),
    category.slots.map(slot => h('div', { class: 'row' }, h('label', {}, h('input', { type: 'checkbox', checked: slot.unlocked, onchange: event => act('slot', { category: category.path, subcategory: slot.subcategory, index: slot.index, enabled: event.target.checked }) }), `${slot.subcategory.split('.').at(-1)} · Slot ${slot.index}`))))));
  return h('div', {}, note('Die Karten-Unterkategorie und zulässige Kombinationen bestimmt das Spiel. Belegte Slots müssen vor dem Sperren geleert werden.'),
    h('div', { class: 'card' }, h('h3', {}, 'Ausgerüstete Karten'), state.active.map(active => h('div', { class: 'row' }, h('span', { class: 'path' }, `${active.path.split('.').at(-1)} · Slot ${active.index}`), button('Ablegen', () => act('unequip', { id: active.id }))))),
    categories, h('div', { class: 'actions' }, select(state.categories.map(category => [category.path, category.title]), category?.path || '', value => { ui.skillCategory = value; renderContent(); }, 'Skillkategorie')),
    pagination(cards, card => {
      const unlocked = category && card.unlockedIn.includes(category.path);
      const available = category?.slots.filter(slot => slot.unlocked) || [];
      let index = available[0]?.index ?? 0;
      return h('article', { class: 'card' }, h('h3', {}, card.title), h('p', { class: 'path' }, card.path),
        h('div', { class: 'actions' }, button(card.revealed ? 'Ausblenden' : 'Aufdecken', () => act('reveal', { path: card.path, enabled: !card.revealed })),
          button(unlocked ? 'In Kategorie sperren' : 'In Kategorie freischalten', () => act('unlock', { category: category.path, path: card.path, enabled: !unlocked }), { disabled: !category }),
          select([...new Set(available.map(slot => slot.index))].map(value => [String(value), `Slot ${value}`]), String(index), value => { index = Number(value); }, 'Zielslot'),
          button('Ausrüsten / Slot ersetzen', () => {
            const current = state.active.find(active => active.category === category.path && active.index === index);
            act('equip', { category: category.path, index, path: card.path, ...(current ? { replacing: current.id } : {}) });
          }, { disabled: !category || !available.length })));
    }));
}
function worldView() {
  const objects = profileItems('world').filter(object => matches(object.actor, object.location, object.category));
  return h('div', {}, note('Einzelne gespeicherte Schalter bearbeiten. Diese Aktionen emulieren keine Questskripte, NPCs oder Spawnregeln.'),
    pagination(objects, object => h('div', { class: 'card' }, h('h3', {}, object.actor), h('p', { class: 'path' }, `${object.category} · ${object.location}`),
      object.flags.map(flag => h('label', {}, h('input', { type: 'checkbox', checked: flag.value, onchange: event => mutate({ type: 'world', values: { [flag.id]: event.target.checked } }) }), ' ' + flag.title)))));
}
function advancedView() {
  const fields = profileItems('fields').filter(field => matches(field.title, field.context, field.property));
  return h('div', {}, note('Alle erkannten numerischen Werte einschließlich Rücksetzdatensätzen. Unbekannte Binärdaten werden nicht als frei editierbare Werte angeboten.'),
    h('div', { class: 'card' }, pagination(fields, field => h('div', { class: 'card' }, fieldView(field)))), catalogTools());
}
function renderContent() {
  if (!session.model) return;
  $('heading').textContent = ui.section; $('count').textContent = '';
  const content = { Charakter: characterView, Inventar: inventoryView, Freischaltungen: () => unlockView(false), Quests: questsView,
    Skillkarten: skillsView, Sammlungen: () => unlockView(true), Weltzustände: worldView, Erweitert: advancedView }[ui.section]();
  $('content').replaceChildren(content);
}
function render() {
  $('filename').textContent = session.name || 'Keine Datei geöffnet';
  $('profile').disabled = !session.model; $('search').disabled = !session.model;
  $('profile').replaceChildren(...(session.model?.profiles || []).map(profile => option(profile.id, profile.label)));
  $('profile').value = ui.profile;
  $('sections').replaceChildren(...sections.map(section => button(section, () => { ui.section = section; ui.page = 0; render(); }, { class: ui.section === section ? 'active' : '', disabled: !session.model })));
  updateButtons(); renderContent();
  if (session.model) $('status').textContent = `Prüfsumme gültig · ${session.model.version} · ${session.model.profiles.filter(profile => profile.id !== 'Account').length} Charaktere · ${session.model.fields.length} Werte${session.changed ? ' · im Browser bearbeitet' : ' · Original geladen'}`;
}

$('open').onclick = $('welcome-open').onclick = () => $('save-input').click();
$('save-input').onchange = async event => { const file = event.target.files[0]; event.target.value = ''; await openFile(file); };
$('backup').onclick = backup; $('download').onclick = exportSave; $('apply').onclick = applyDrafts;
$('undo').onclick = () => history('undo'); $('redo').onclick = () => history('redo');
$('cancel').onclick = () => cancel();
$('busy').addEventListener('cancel', event => { event.preventDefault(); cancel(); });
$('reset').onclick = async () => {
  if (!session.changed) { drafts.clear(); render(); return; }
  if (!confirm('Alle Bearbeitungen verwerfen und das unveränderte Original erneut laden?')) return;
  try { const result = await run({ save: session.original }); session.apply(result); drafts.clear(); render(); } catch (cause) { error(cause); }
};
$('profile').onchange = event => { ui.profile = event.target.value; ui.collection = ''; ui.item = ''; ui.quest = ''; ui.skillCategory = ''; ui.page = 0; render(); };
$('search').oninput = event => { ui.query = event.target.value; ui.page = 0; renderContent(); };
$('platform').onchange = () => { $('status').textContent = 'Versionszuordnung ist nur eine Anzeige. Sie konvertiert oder verändert den Save nicht.'; };
for (const kind of ['items', 'upgrades']) {
  $(kind + '-input').onchange = async event => {
    const file = event.target.files[0]; event.target.value = ''; if (!file) return;
    try {
      if (file.size > 4 * 1024 * 1024) throw new Error('CSV-Dateien sind auf 4 MB begrenzt.');
      const result = await run({ [kind + 'CSV']: await file.text() }, 'Katalog wird geprüft …');
      if (kind === 'items') catalog = result.items; else upgrades = result.upgrades;
      render(); $('status').textContent = 'Katalog lokal eingelesen. Keine Save-Datei wurde hochgeladen.';
    } catch (cause) { error(cause); }
  };
}
$('unlocks-input').onchange = async event => {
  const file = event.target.files[0]; event.target.value = ''; if (!file) return;
  try {
    if (file.size > 128 * 1024 * 1024) throw new Error('Diese Datei ist zu groß.');
    const result = await run({ save: toBase64(new Uint8Array(await file.arrayBuffer())) }, 'Freischaltungen werden eingelesen …');
    known = mergeTables([...known, ...Object.values(result.model.unlocks).flat()]);
    render(); $('status').textContent = 'Freischaltungsangebot ergänzt; noch keine IDs aktiviert.';
  } catch (cause) { error(cause); }
};
window.addEventListener('beforeunload', event => { if (session.unsaved || drafts.size) { event.preventDefault(); event.returnValue = ''; } });
window.addEventListener('keydown', event => {
  const editing = /INPUT|TEXTAREA|SELECT/.test(event.target.tagName);
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z' && !editing) { event.preventDefault(); history(event.shiftKey ? 'redo' : 'undo'); }
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's' && session.current) { event.preventDefault(); exportSave(); }
});
async function initialize() {
  try {
    if (!globalThis.WebAssembly || !globalThis.Worker || !globalThis.crypto?.getRandomValues) throw new Error('Ein aktueller Browser mit WebAssembly, Web Workers und sicherem Zufallsgenerator wird benötigt.');
    const load = async name => { const response = await fetch(new URL(`./${name}.json`, import.meta.url)); if (!response.ok) throw new Error('Katalog konnte nicht geladen werden: ' + name); return response.json(); };
    const [collections, unlocks, questRewards] = await Promise.all([load('CollectionCatalog'), load('UnlockCatalog'), load('QuestRewards')]);
    known = mergeTables([...collections.tables, ...Object.values(unlocks).flat()]); rewards = questRewards;
    await run(null, 'Editor wird vorbereitet …');
    $('status').textContent = 'Bereit · lokale Verarbeitung · keine Datei-Uploads';
    render();
  } catch (cause) { error(cause); $('status').textContent = 'Initialisierung fehlgeschlagen. Bitte die Seite über HTTPS oder localhost öffnen.'; }
}
initialize();
