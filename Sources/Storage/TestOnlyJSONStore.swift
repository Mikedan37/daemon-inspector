import Foundation

/// QUARANTINED: This code is FORBIDDEN in production.
/// 
/// This file contains the old JSON file-based persistence that violates
/// append-only semantics by loading all records, appending one, and rewriting.
/// 
/// This code exists ONLY for:
/// - Reference of what was removed
/// - Testing migration paths
/// 
/// DO NOT USE THIS IN PRODUCTION CODE PATHS.
/// 
/// The correct implementation uses BlazeDB which owns persistence mechanics.

// MARK: - Forbidden Implementation (Reference Only)

struct FileDatabase {
    let baseURL: URL
    
    init(at url: URL) throws {
        self.baseURL = url
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
    
    func table<T: Codable>(name: String, of type: T.Type) throws -> TestOnlyTable<T> {
        let tableURL = baseURL.appendingPathComponent("\(name).json")
        return TestOnlyTable<T>(url: tableURL)
    }
}

/// FORBIDDEN PATTERN: loadAll → append → saveAll
/// This rewrites history and violates append-only semantics.
struct TestOnlyTable<T: Codable> {
    let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    // FORBIDDEN: Loads all records to append one
    func insert(_ item: T) throws {
        var items = try loadAll()
        items.append(item)
        try saveAll(items)  // Rewrites entire file
    }
    
    // FORBIDDEN: Loads entire dataset into memory
    func loadAll() throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([T].self, from: data)
    }
    
    // FORBIDDEN: Rewrites entire file
    func saveAll(_ items: [T]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: url)
    }
}
