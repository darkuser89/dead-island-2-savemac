// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SaveCore

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 1 || arguments.count == 3 || arguments.count == 5 else {
        throw NSError(domain: "Usage", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "SaveMacVerify INPUT.sav [--export OUTPUT.sav [--xp VALUE | --set PROPERTY=VALUE]]"])
    }
    let source = URL(fileURLWithPath: arguments[0])
    let before = try Data(contentsOf: source)
    let document = try SaveDocument(data: before)
    print("Checksum valid; sections=\(document.sections.count), characters=\(document.sections.filter(\.isCharacter).count), editableFields=\(document.fields.count)")
    var edits: [Int: String] = [:]
    var operations: [InventoryOperation] = []
    var unlocks: [UnlockOperation] = []
    if arguments.count == 5 {
        if arguments[3] == "--request" {
            let request = try JSONDecoder().decode(CompatibilityRequest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[4])))
            (operations, unlocks) = try request.operations(for: document)
        } else if ["--duplicate", "--copy-stash", "--move-stash", "--remove"].contains(arguments[3]) {
            let candidates = document.inventories.filter { $0.section != "Account" }
            let match = candidates.compactMap { collection -> (InventoryCollection, InventoryEntry)? in
                guard let entry = collection.entries.first(where: {
                    !$0.isSystemItem && (arguments[4] == "first" || $0.title.localizedCaseInsensitiveContains(arguments[4]))
                }) else { return nil }
                return (collection, entry)
            }.first
            guard let (collection, entry) = match else { throw SaveError.invalid("No matching inventory item") }
            if arguments[3] == "--duplicate" {
                operations = [.copy(source: collection.id, item: entry.id, destination: collection.id)]
            } else if arguments[3] == "--remove" {
                operations = [.remove(source: collection.id, item: entry.id)]
            } else {
                guard let target = document.inventories.first(where: { $0.section == "Account" && $0.role == "Lager" && $0.itemType == collection.itemType }) else {
                    throw SaveError.invalid("No compatible stash")
                }
                operations = [arguments[3] == "--copy-stash"
                    ? .copy(source: collection.id, item: entry.id, destination: target.id)
                    : .move(source: collection.id, item: entry.id, destination: target.id)]
            }
        } else {
        let pair = arguments[4].split(separator: "=", maxSplits: 1).map(String.init)
        let property = arguments[3] == "--xp" ? "XPValue" : (pair.first ?? "")
        let value = arguments[3] == "--xp" ? arguments[4] : (pair.count == 2 ? pair[1] : "")
        guard ["--xp", "--set"].contains(arguments[3]),
              let field = document.fields.first(where: { $0.property == property && !$0.advanced }) else {
            throw NSError(domain: "Usage", code: 2, userInfo: [NSLocalizedDescriptionKey: "No XP field or unknown option"])
        }
        edits[field.id] = value
        }
    }
    if arguments.count >= 3 {
        guard arguments[1] == "--export" else {
            throw NSError(domain: "Usage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown option"])
        }
        let destination = URL(fileURLWithPath: arguments[2])
        try ExportPolicy.validate(source: source, destination: destination)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw NSError(domain: "Usage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Output already exists"])
        }
        let output = try document.export(edits: edits, operations: operations, unlocks: unlocks)
        try output.write(to: destination, options: .withoutOverwriting)
        let verified = try SaveDocument(data: Data(contentsOf: destination))
        guard verified.container.header == document.container.header,
              operations.isEmpty && unlocks.isEmpty ? verified.container.payload == (try document.patchedPayload(edits: edits)) : true else {
            throw NSError(domain: "Verification", code: 1)
        }
        for operation in unlocks {
            guard operation.tables.allSatisfy({ table in
                Set(verified.unlocks[operation.section]?.first { $0.name == table.name }?.rows ?? []) == Set(table.rows)
            }) else { throw SaveError.invalid("Unlock verification failed") }
        }
        print("Export valid; modifiedFields=\(edits.count), inventoryOperations=\(operations.count), unlockOperations=\(unlocks.count), opaque header preserved")
    }
    guard try Data(contentsOf: source) == before else { throw NSError(domain: "OriginalChanged", code: 1) }
    print("Original unchanged")
} catch {
    fputs(error.localizedDescription + "\n", stderr)
    exit(1)
}
