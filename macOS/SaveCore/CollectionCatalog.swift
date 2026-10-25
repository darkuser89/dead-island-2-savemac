// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Collection entitlement IDs must come from a save or an explicit user-provided ID, never inferred asset filenames.
public enum CollectionCatalog {
    public static func contains(_ name: String) -> Bool {
        let base = "DT_GameEntitlement_"
        return ["Journal", "FuseRooms", "Keys", "KeyCards"].contains { name == base + $0 || name.hasPrefix(base + $0 + "_") }
    }
    public static func tables(in tables: [UnlockTable]) -> [UnlockTable] { tables.filter { contains($0.name) } }
    public static func title(_ name: String) -> String {
        name.replacingOccurrences(of: "DT_GameEntitlement_", with: "")
            .replacingOccurrences(of: "Journal", with: "Tagebuch")
            .replacingOccurrences(of: "FuseRooms", with: "Sicherungsräume")
            .replacingOccurrences(of: "KeyCards", with: "Schlüsselkarten")
            .replacingOccurrences(of: "Keys", with: "Schlüssel")
    }
}

extension CollectionCatalog {
    public struct Manifest: Decodable {
        public struct GameVersion: Decodable { public let version: String; public let build: String }
        public struct Provenance: Decodable {
            public let table: String
            public let packagePath: String
            public let masExportSHA256: String
            public let steamExportSHA256: String
        }
        public let schema: Int
        public let identifier: String
        public let gameVersions: [String: GameVersion]
        public let tables: [UnlockTable]
        public let provenance: [Provenance]
        public var entryCount: Int { tables.reduce(0) { $0 + $1.rows.count } }
    }
    public static func load(_ data: Data) throws -> Manifest {
        guard data.count <= 512 * 1024 else { throw SaveError.invalid("Der Sammlungskatalog ist zu groß.") }
        let value = try JSONDecoder().decode(Manifest.self, from: data)
        let names = value.tables.map(\.name)
        func validHash(_ text: String) -> Bool { text.count == 64 && text.allSatisfy { $0.isHexDigit && $0.isASCII } }
        guard value.schema == 1, !value.identifier.isEmpty, !value.tables.isEmpty,
              Set(names).count == names.count, value.entryCount <= 10000,
              value.tables.allSatisfy({ table in contains(table.name) && table.rows.count <= 10000
                  && Set(table.rows.map { $0.lowercased() }).count == table.rows.count
                  && table.rows.allSatisfy { !$0.isEmpty && !$0.contains("\0") && $0.utf8.count < 512 } }),
              Set(value.provenance.map(\.table)) == Set(names), value.provenance.count == names.count,
              value.provenance.allSatisfy({ $0.packagePath.hasPrefix("/Game/DI2/") && validHash($0.masExportSHA256) && validHash($0.steamExportSHA256) }) else {
            throw SaveError.invalid("Der Sammlungskatalog ist unvollständig oder enthält ungültige IDs bzw. Herkunftsnachweise.")
        }
        return value
    }
}
