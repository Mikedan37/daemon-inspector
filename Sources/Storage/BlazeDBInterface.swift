import Foundation

/// Protocol defining the minimal interface that BlazeDB must provide.
/// 
/// The application does NOT own persistence mechanics. BlazeDB does.
/// The application only hands immutable facts to BlazeDB one-at-a-time.
/// 
/// BlazeDB is responsible for:
/// - Encoding (may use Codable internally)
/// - Durability
/// - Append-only storage
/// - Partial write survival
/// 
/// The application is responsible for:
/// - Constructing immutable records
/// - Calling insert() one record at a time
/// - Never rewriting history

/// A table in BlazeDB that supports append-only inserts and queries.
public protocol BlazeTable<Record> {
    associatedtype Record: Codable
    
    /// Insert a single record. This must be append-only.
    /// BlazeDB owns the encoding and storage mechanics.
    /// The application never loads all records to insert one.
    func insert(_ record: Record) throws
    
    /// Create a query builder for this table.
    func query() -> any BlazeQuery<Record>
}

/// Query builder interface that BlazeDB must provide.
/// 
/// BlazeDB may load records into memory for querying, but the application
/// never sees or manages that process. BlazeDB owns query execution.
public protocol BlazeQuery<Record> {
    associatedtype Record: Codable
    
    /// Order results by a key path.
    func order<V: Comparable>(by keyPath: KeyPath<Record, V>, descending: Bool) -> Self
    
    /// Limit the number of results.
    func limit(_ count: Int) -> Self
    
    /// Filter results with a predicate.
    func `where`(_ predicate: @escaping (Record) -> Bool) -> Self
    
    /// Execute the query and return results.
    /// BlazeDB owns how this executes (may use indexes, may load into memory, etc.)
    func all() throws -> [Record]
}

/// BlazeDB database interface.
/// 
/// The application opens BlazeDB once and uses it for all operations.
/// BlazeDB owns the database file, encoding, and storage layout.
public protocol BlazeDatabase {
    /// Open or create a table. BlazeDB owns table creation and schema.
    func table<Record: Codable>(name: String, of type: Record.Type) throws -> any BlazeTable<Record>
}
