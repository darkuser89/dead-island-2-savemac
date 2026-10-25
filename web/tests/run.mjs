// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const directory = process.argv[2];
if (!directory) throw new Error('Usage: node web/tests/run.mjs BUILD_DIR/Web/Site [REAL_SAVE ...]');
const site = path.resolve(directory);
const { execute } = await import(pathToFileURL(path.join(site, 'engine.js')));
const { SaveSession, toBase64, fromBase64 } = await import(pathToFileURL(path.join(site, 'session.js')));
const module = await WebAssembly.compile(fs.readFileSync(path.join(site, 'SaveCore.wasm')));
const fixtures = await WebAssembly.compile(fs.readFileSync(path.join(site, '../TestFixtures.wasm')));
const files = execute(fixtures, {}).files;
const save = files['0x0012fee2'];
const inspect = bytes => execute(module, { save: bytes });
const initial = inspect(save);
const profile = initial.model.profiles.find(item => item.id !== 'Account').id;
const field = (result, property) => result.model.fields.find(item => item.property === property);
const weapons = result => result.model.inventories.find(item => item.section === profile && item.itemType === 'InventoryItemInstanced');
const materials = result => result.model.inventories.find(item => item.section === profile && item.itemType === 'InventoryItemArchetype');
const action = (action, input = save, extra = {}) => execute(module, { save: input, action, ...extra });
let count = 0;
function test(label, body) { body(); count++; console.log(`PASS ${label}`); }

test('All four save versions open and preserve input bytes', () => {
  for (const [version, input] of Object.entries(files)) {
    const result = inspect(input); assert.equal(result.save, input); assert.equal(result.model.version, version);
    assert.equal(result.model.profiles.length, 2); assert.equal(result.model.quests.length, 1); assert.equal(result.model.world.length, 1);
    assert.equal(result.model.skills[profile].cards.length, 2);
  }
});
test('XP, rarity and full durability survive composed edit and re-open', () => {
  const values = { [field(initial, 'XPValue').id]: '3000', [field(initial, 'RequiredRarity').id]: 'Legendary', [field(initial, 'Durability').id]: 'voll' };
  const result = action({ type: 'fields', values });
  assert.equal(field(result, 'XPValue').value, '3000'); assert.equal(field(result, 'RequiredRarity').value, 'Legendary');
  assert.equal(field(result, 'Durability').value, 'voll'); assert.equal(inspect(result.save).model.version, initial.model.version);
});
test('Unknown offsets, invalid XP, invalid level and nonfinite durability rejected', () => {
  for (const [id, value] of [[0, '1'], [field(initial, 'XPValue').id, '-1'], [field(initial, 'RequiredLevel').id, '100'], [field(initial, 'Durability').id, 'nan']]) {
    assert.throws(() => action({ type: 'fields', values: { [id]: value } }));
  }
});
test('Duplicate creates a new item ID without losing source', () => {
  const collection = weapons(initial), item = collection.entries[0];
  const result = action({ type: 'inventory', operation: 'copy', source: collection.id, item: item.id, destination: collection.id });
  assert.equal(weapons(result).entries.length, 2); assert.equal(new Set(weapons(result).entries.map(item => item.id)).size, 2);
  assert.ok(weapons(result).entries.some(entry => entry.id === item.id));
});
test('Move transfers weapon to account stash', () => {
  const collection = weapons(initial), target = initial.model.inventories.find(item => item.section === 'Account' && item.itemType === collection.itemType);
  const result = action({ type: 'inventory', operation: 'move', source: collection.id, item: collection.entries[0].id, destination: target.id });
  assert.equal(weapons(result).entries.length, 0); assert.equal(result.model.inventories.find(item => item.id === target.id).entries.length, 1);
});
test('Remove unreferenced weapon', () => {
  const collection = weapons(initial);
  assert.equal(weapons(action({ type: 'inventory', operation: 'remove', source: collection.id, item: collection.entries[0].id })).entries.length, 0);
});
test('Upgrade list and managed count remain consistent', () => {
  const collection = weapons(initial), paths = ['/Game/DI2/Upgrades/TestA.TestA', '/Game/DI2/Upgrades/TestB.TestB'];
  const result = action({ type: 'inventory', operation: 'upgrades', source: collection.id, item: collection.entries[0].id, paths });
  assert.deepEqual(weapons(result).entries[0].upgrades, paths); assert.equal(field(result, 'NumUpgrades').value, '2');
  assert.throws(() => action({ type: 'fields', values: { [field(initial, 'NumUpgrades').id]: '9' } }));
});
const cash = { name: 'Geld', category: 'Special', archetype: '/Game/DI2/Items/Special/DA_InventoryTypes_Special_CashItem.DA_InventoryTypes_Special_CashItem', instanced: false, maximumCount: 999999999, dlc: false, internalItem: false };
test('Add cash and replace existing cash amount', () => {
  const request = { type: 'add', definitions: [cash], destination: materials(initial).id, count: 1234, level: 1, rarity: 'Common', seed: 0 };
  const result = action(request); assert.ok(materials(result).entries.some(entry => entry.currency));
  const again = action({ ...request, count: 5000 }, result.save);
  assert.equal(materials(again).entries.filter(entry => entry.currency).length, 1);
  const entry = materials(again).entries.find(entry => entry.currency);
  assert.equal(again.model.fields.find(field => entry.fields.includes(field.id) && field.property === 'Count').value, '5000');
});
test('Add weapon validates integer inputs and level', () => {
  const definition = { ...cash, name: 'Test weapon', archetype: weapons(initial).entries[0].archetype, instanced: true };
  const request = { type: 'add', definitions: [definition], destination: weapons(initial).id, count: 1, level: 50, rarity: 'Legendary', seed: -123 };
  assert.equal(weapons(action(request)).entries.length, 2);
  assert.throws(() => action({ ...request, level: 100 })); assert.throws(() => action({ ...request, level: true }));
});
test('Freischaltungen grow and shrink; duplicate IDs rejected', () => {
  const request = { type: 'unlocks', section: profile, tables: [{ name: 'DT_GameEntitlement_Journal', rows: ['Existing', 'New'] }] };
  const result = action(request); assert.deepEqual(result.model.unlocks[profile][0].rows, ['Existing', 'New']);
  assert.deepEqual(action({ ...request, tables: [{ ...request.tables[0], rows: [] }] }, result.save).model.unlocks[profile][0].rows, []);
  assert.throws(() => action({ ...request, tables: [{ ...request.tables[0], rows: ['X', 'X'] }] }));
});
test('Quest completion includes objectives; reset clears checkpoint', () => {
  const quest = initial.model.quests[0];
  const done = action({ type: 'quest', id: quest.id, state: 'Complete', includeObjectives: true });
  assert.equal(done.model.quests[0].state, 'Complete'); assert.equal(done.model.quests[0].objectives[0].state, 'Complete');
  const reset = action({ type: 'quest', id: quest.id, state: 'Waiting', includeObjectives: true }, done.save);
  assert.deepEqual(reset.model.quests[0].checkpoints[0].completed, []); assert.equal(reset.model.quests[0].objectives[0].state, 'Waiting');
});
test('Individual objective, display index and checkpoint edits', () => {
  const quest = initial.model.quests[0];
  assert.equal(action({ type: 'objective', id: quest.objectives[0].id, state: 'Stopped' }).model.quests[0].objectives[0].state, 'Stopped');
  assert.equal(action({ type: 'displayIndex', id: quest.id, index: 77 }).model.quests[0].index, 77);
  assert.deepEqual(action({ type: 'checkpoint', id: quest.checkpoints[0].id, completed: ['NEW'] }).model.quests[0].checkpoints[0].completed, ['NEW']);
});
const rule = { id: 'MIS_TEST01', questPath: '/Game/DI2/Missions/MIS_TEST01', questExportSHA256: 'a'.repeat(64), rewardPath: '/Game/DI2/Rewards/Test', exportSHA256: 'b'.repeat(64), xp: 1000, cash: 200, other: [] };
const rewardCatalog = { schema: 1, context: 'standard-first-completion', definitions: [rule] };
test('Standard first completion credits XP and cash exactly once', () => {
  const request = { type: 'reward', id: initial.model.quests[0].id, confirmed: true };
  const result = action(request, save, { rewardCatalog });
  assert.equal(field(result, 'XPValue').value, '1500'); assert.equal(result.model.quests[0].state, 'Complete');
  assert.ok(materials(result).entries.some(entry => entry.currency));
  assert.throws(() => action(request, result.save, { rewardCatalog }));
  assert.throws(() => action(request, files['0x0011e5f3'], { rewardCatalog }));
  assert.throws(() => action({ ...request, confirmed: false }, save, { rewardCatalog }));
});
test('Unknown reward loot remains blocked', () => {
  assert.throws(() => action({ type: 'reward', id: initial.model.quests[0].id, confirmed: true }, save,
    { rewardCatalog: { ...rewardCatalog, definitions: [{ ...rule, other: ['LootRoll'] }] } }));
});
test('Reveal, unlock and equip replacement skill card', () => {
  const state = initial.model.skills[profile], card = state.cards.find(card => !card.revealed), category = state.categories[0];
  const result = action({ type: 'skill', operation: 'equip', section: profile, category: category.path, index: 0, path: card.path, replacing: state.active[0].id });
  assert.equal(result.model.skills[profile].active[0].path, card.path);
  assert.ok(result.model.skills[profile].cards.find(entry => entry.path === card.path).revealed);
  assert.equal(action({ type: 'skill', operation: 'unequip', section: profile, id: result.model.skills[profile].active[0].id }, result.save).model.skills[profile].active.length, 0);
});
test('Skill reveal/unlock, category cleanup and occupied-slot protection', () => {
  const state = initial.model.skills[profile], card = state.cards.find(card => !card.revealed), category = state.categories[0];
  assert.ok(action({ type: 'skill', operation: 'reveal', section: profile, path: card.path, enabled: true }).model.skills[profile].cards.find(item => item.path === card.path).revealed);
  assert.ok(action({ type: 'skill', operation: 'unlock', section: profile, category: category.path, path: card.path, enabled: true }).model.skills[profile].categories[0].skills.includes(card.path));
  const locked = action({ type: 'skill', operation: 'category', section: profile, category: category.path, enabled: false });
  assert.equal(locked.model.skills[profile].categories[0].unlocked, false); assert.equal(locked.model.skills[profile].active.length, 0);
  const occupied = category.slots.find(slot => slot.unlocked);
  assert.throws(() => action({ type: 'skill', operation: 'slot', section: profile, category: category.path, subcategory: occupied.subcategory, index: occupied.index, enabled: false }));
  const slot = category.slots.find(slot => !slot.unlocked);
  const result = action({ type: 'skill', operation: 'slot', section: profile, category: category.path, subcategory: slot.subcategory, index: slot.index, enabled: true });
  assert.ok(result.model.skills[profile].categories[0].slots.find(item => item.id === slot.id).unlocked);
});
test('World flag changes and unknown IDs rejected', () => {
  const flag = initial.model.world[0].flags[0];
  assert.equal(action({ type: 'world', values: { [flag.id]: !flag.value } }).model.world[0].flags[0].value, !flag.value);
  assert.throws(() => action({ type: 'world', values: { unknown: true } }));
});
test('Catalog CSV parsing uses shared validators', () => {
  const itemCSV = 'category,name,instanced,archetype\nSpecial,Test,0,/Game/DI2/Items/Test.Test\n';
  assert.equal(execute(module, { itemsCSV: itemCSV }).items.length, 1);
  const upgradeCSV = 'upgrade_type,weapon_type,archetype,name\nperk,melee,/Game/DI2/Upgrades/Test.Test,Test\n';
  assert.equal(execute(module, { upgradesCSV: upgradeCSV }).upgrades.length, 1);
  assert.throws(() => execute(module, { itemsCSV: 'wrong,header\na,b' }));
});
test('Damaged checksum, truncated and unknown save formats rejected', () => {
  const bytes = Buffer.from(save, 'base64'); bytes[bytes.length - 1] ^= 1;
  assert.throws(() => inspect(bytes.toString('base64'))); assert.throws(() => inspect(Buffer.from('not a save').toString('base64')));
});
test('Browser backup is byte-identical and undo/redo restores actual file bytes', () => {
  const state = new SaveSession(); state.open('fixture.sav', save, initial.model);
  const changed = action({ type: 'fields', values: { [field(initial, 'XPValue').id]: '3000' } }); state.apply(changed);
  assert.equal(state.original, save); assert.ok(state.unsaved); state.restore(initial, 'undo'); assert.equal(state.current, save);
  state.restore(changed, 'redo'); assert.equal(state.current, changed.save);
  state.exported = state.current; assert.equal(state.unsaved, false);
  assert.deepEqual(Buffer.from(fromBase64(toBase64(Buffer.from(save, 'base64')))), Buffer.from(save, 'base64'));
});
test('Browser history is bounded and rejects unrelated restoration', () => {
  const state = new SaveSession(); state.open('test', '0', {});
  for (let i = 1; i <= 100; i++) state.apply({ save: String(i), model: {} });
  assert.equal(state.undoStack.length, 30); assert.throws(() => state.restore({ save: 'wrong' }, 'undo'));
});
test('Bundled catalogs have the documented scope', () => {
  const collections = JSON.parse(fs.readFileSync(path.join(site, 'CollectionCatalog.json')));
  assert.equal(collections.tables.length, 12); assert.equal(collections.tables.reduce((sum, table) => sum + table.rows.length, 0), 572);
  assert.equal(JSON.parse(fs.readFileSync(path.join(site, 'QuestRewards.json'))).definitions.length, 99);
});
for (const filename of process.argv.slice(3)) {
  test(`Reference read and XP edit: ${path.basename(filename)}`, () => {
    const bytes = fs.readFileSync(filename), before = createHash('sha256').update(bytes).digest('hex');
    const input = bytes.toString('base64'), opened = inspect(input), xp = field(opened, 'XPValue');
    assert.equal(opened.save, input); assert.ok(xp); const next = String(Number(xp.value) + 1);
    if (process.env.DI2_NATIVE_BRIDGE) {
      const native = spawnSync(process.env.DI2_NATIVE_BRIDGE, [], { input: JSON.stringify({ save: input }) + '\n', encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
      assert.equal(native.status, 0, native.stderr);
      assert.deepEqual(opened.model, JSON.parse(native.stdout).model, 'Native and browser snapshots must agree');
    }
    const changed = action({ type: 'fields', values: { [xp.id]: next } }, input);
    assert.equal(field(changed, 'XPValue').value, next); assert.equal(changed.model.version, opened.model.version);
    assert.equal(createHash('sha256').update(fs.readFileSync(filename)).digest('hex'), before);
    console.log(`  ${opened.model.profiles.length - 1} characters, ${opened.model.quests.length} quests, ${opened.model.world.length} world objects; original unchanged`);
  });
}
console.log(`\n${count} web integration tests passed.`);
