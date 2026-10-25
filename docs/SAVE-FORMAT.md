# Supported save format

All integer fields below are little-endian. The codec preserves the opaque
version header and never substitutes a PC header for a Mac one.

| Field | Representation |
| --- | --- |
| Magic | `uint32`, `0x0012fee2` |
| Opaque header | 8 bytes, preserved unchanged |
| Compression name | Unreal-style length-prefixed UTF-8 string `Zstd\0` |
| Each chunk | compressed length `uint32`, unpacked length `uint32`, Zstd frame |
| End marker | `uint32`, `0x5a13fc42`, replacing the next compressed length |
| Payload hash | CityHash64 of the concatenated unpacked bytes, `uint64` |

Chunks unpack to at most 65,536 bytes. The implementation limits the unpacked
payload to 64 MiB, rejects trailing data and verifies the checksum before editing.
The payload begins with a section count; each section has a length-prefixed name,
a `uint32` byte length and opaque bytes. `CharacterProfileAccount` must exist,
names must be unique, and the sections must consume the payload exactly.
Character section names contain 32 hexadecimal characters.

## Property patches

The reader recognizes complete Unreal property tags, including their type,
serialized length, type-specific descriptor, array index and optional GUID.
Selected numeric fields and rarity enum strings can be changed. Runtime fields
use a separate typed-map reader. Unknown values remain opaque.

Variable-length changes update each enclosing property length and the containing
section length. Overlapping patches and ambiguous length ownership are rejected.
Fixed-width values change only their selected spans. The final payload is
recompressed, hashed and read back before replacement.

## Inventories

Supported `InstancedItems` and `ArchetypeItems` arrays contain a struct descriptor,
a count and tagged item records ending in `None`. Entry IDs identify operations
across reparsing; copied items receive fresh nonzero identifiers. Removal and
moves reject known raw ID references outside the source item. System fists are
excluded from these operations. Account arrays distinguish Stash and LostAndFound;
LostAndFound is not a destination for new items.

New weapons contain an archetype, procedural generation context, entry/unique
IDs and a runtime map. The runtime map key type is **StrProperty**, its value type
is StructProperty and its descriptor is `InventoryPersistentStateEntry`.
Its body has a removed-entry count, entry count and records consisting of a
string key, numeric type ID, byte length and raw value. Type 10 is float32,
type 14 is int32 and type 24 is a serialized string. Full durability uses
Float.greatestFiniteMagnitude. `NumUpgrades` and consecutive `UpgradeEntryN`
strings are changed together; unrelated runtime records are preserved.

Non-instanced additions update an existing matching archetype's Count rather
than adding a duplicate stack. Batch additions update the array count and lengths
together. Money is a non-instanced character inventory entry, never an account
stash balance. New item metadata is supplied by the caller or optional CSV files;
no game assets are copied or synthesized.

## Freischaltungen

`GrantedEntitlements` is a map with NameProperty keys and StructProperty values.
The inner `GrantedEntitlements` struct contains table names and tagged value
records. Their `Entitlements` array contains NameProperty strings. Edits preserve
unknown properties within existing values and update list/map counts and all
containing lengths. Only `DT_GameEntitlement_` table names are accepted.

The bundled catalog contains game table/row identifiers for known blueprint and
curveball unlocks, rather than player save data. It does not confer DLC ownership
or implement arbitrary quest and skill-state changes.

## Backup container

The `.savemac-backup` file is a binary property list, not a game-loadable save.
It contains a tool identifier, schema version 1, canonical source path, date,
SHA-256 and the exact original save bytes. Existing backups must validate before
updates. Replacement retains one previous state. Recovery of a damaged current
save retains the valid backup instead. A per-source lock prevents simultaneous
editor writes, and source bytes are checked again before replacement.
