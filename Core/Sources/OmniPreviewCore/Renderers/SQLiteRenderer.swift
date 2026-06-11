import Foundation
import SQLite3

/// Read-only SQLite preview: schema overview with per-table row counts.
public struct SQLiteRenderer: PreviewRenderer {
    public static let id = "sqlite"
    public static let displayName = "SQLite Database"

    static let maxTables = 200

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .sqlite }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        var db: OpaquePointer?
        let openResult = openDatabase(url: file.url, db: &db)
        defer { sqlite3_close_v2(db) }
        guard openResult == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
            throw PreviewError.unreadable("SQLite open failed (code \(openResult)): \(message)")
        }

        var tables: [(name: String, columns: Int, rows: String)] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
            -1, &statement, nil
        ) == SQLITE_OK else {
            throw PreviewError.corruptFile("could not read sqlite_master")
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW, tables.count < Self.maxTables {
            guard let cName = sqlite3_column_text(statement, 0) else { continue }
            let name = String(cString: cName)
            tables.append((name, columnCount(db: db, table: name), rowCount(db: db, table: name)))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "SQLite Database",
            iconSystemName: "cylinder.split.1x2",
            sections: [
                .keyValues(title: "Summary", rows: [
                    KeyValueRow("Tables", "\(tables.count)"),
                    KeyValueRow("File size", Format.bytes(file.fileSize)),
                ]),
                .table(
                    title: "Tables",
                    columns: ["Name", "Columns", "Rows"],
                    rows: tables.map { [$0.name, "\($0.columns)", $0.rows] }
                ),
            ]
        )
    }

    private func openDatabase(url: URL, db: inout OpaquePointer?) -> Int32 {
        // 1) Prefer direct readonly path: this correctly picks up companion
        // WAL/SHM files when present.
        var rc = sqlite3_open_v2(
            url.path, &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil
        )
        if rc == SQLITE_OK { return rc }
        sqlite3_close_v2(db)
        db = nil

        // 2) Fallback URI immutable=1 for environments where side files are
        // unavailable (e.g. stricter sandbox contexts).
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = "file"
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        rc = sqlite3_open_v2(
            components.url!.absoluteString, &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil
        )
        return rc
    }

    private func columnCount(db: OpaquePointer?, table: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(quoted(table)))", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        var count = 0
        while sqlite3_step(statement) == SQLITE_ROW { count += 1 }
        return count
    }

    private func rowCount(db: OpaquePointer?, table: String) -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(quoted(table))", -1, &statement, nil) == SQLITE_OK else {
            return "?"
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return "?" }
        return "\(sqlite3_column_int64(statement, 0))"
    }

    private func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
