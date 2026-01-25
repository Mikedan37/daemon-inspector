import Foundation
import BlazeDBCore

/// Adapter that implements our storage protocols using BlazeDB.
/// 
/// BlazeDB uses a single collection. We distinguish record types using a "_type" field.
/// BlazeDB owns encoding, durability, and storage mechanics.
struct BlazeDBAdapter {
    let client: BlazeDBClient
    
    init(client: BlazeDBClient) {
        self.client = client
    }
}

/// BlazeDB implementation of BlazeDatabase protocol
extension BlazeDBAdapter: BlazeDatabase {
    func table<Record: Codable>(name: String, of type: Record.Type) throws -> any BlazeTable<Record> {
        BlazeDBTableAdapter<Record>(client: client, typeName: name)
    }
}

/// BlazeDB implementation of BlazeTable protocol
struct BlazeDBTableAdapter<Record: Codable>: BlazeTable {
    let client: BlazeDBClient
    let typeName: String
    
    func insert(_ record: Record) throws {
        // Convert Codable record to BlazeDataRecord
        let blazeRecord = try recordToBlazeDataRecord(record, typeName: typeName)
        // BlazeDB owns the insert mechanics - one record at a time, append-only
        _ = try client.insert(blazeRecord)
    }
    
    func query() -> any BlazeQuery<Record> {
        BlazeDBQueryAdapter<Record>(client: client, typeName: typeName)
    }
    
    /// Convert a Codable record to BlazeDataRecord for storage.
    /// BlazeDB owns encoding - we just convert the structure.
    private func recordToBlazeDataRecord(_ record: Record, typeName: String) throws -> BlazeDataRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StorageError.encodingFailed
        }
        
        var fields: [String: BlazeDocumentField] = [
            "_type": .string(typeName)  // Type discriminator for filtering
        ]
        
        for (key, value) in dict {
            fields[key] = try valueToBlazeField(value)
        }
        
        return BlazeDataRecord(fields)
    }
    
    /// Convert Swift values to BlazeDocumentField
    private func valueToBlazeField(_ value: Any) throws -> BlazeDocumentField {
        switch value {
        case let uuid as UUID:
            return .uuid(uuid)
        case let str as String:
            return .string(str)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let date as Date:
            return .date(date)
        case let data as Data:
            return .data(data)
        case let array as [Any]:
            return .array(try array.map { try valueToBlazeField($0) })
        case let dict as [String: Any]:
            var fields: [String: BlazeDocumentField] = [:]
            for (k, v) in dict {
                fields[k] = try valueToBlazeField(v)
            }
            return .dictionary(fields)
        case is NSNull:
            return .null
        default:
            // Try to handle numeric types that might be bridged
            if let nsNumber = value as? NSNumber {
                if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                    return .bool(nsNumber.boolValue)
                } else if nsNumber.objCType.pointee == 0x64 { // 'd' for double
                    return .double(nsNumber.doubleValue)
                } else {
                    return .int(nsNumber.intValue)
                }
            }
            throw StorageError.unsupportedType(String(describing: type(of: value)))
        }
    }
}

/// BlazeDB implementation of BlazeQuery protocol
struct BlazeDBQueryAdapter<Record: Codable>: BlazeQuery {
    let client: BlazeDBClient
    let typeName: String
    private var orderField: String?
    private var orderDescending: Bool = false
    private var limitCount: Int?
    private var predicate: ((Record) -> Bool)?
    
    init(client: BlazeDBClient, typeName: String) {
        self.client = client
        self.typeName = typeName
    }
    
    func order<V: Comparable>(by keyPath: KeyPath<Record, V>, descending: Bool) -> Self {
        var copy = self
        // Extract field name from keyPath string representation
        let keyPathString = String(describing: keyPath)
        copy.orderField = extractFieldName(from: keyPathString)
        copy.orderDescending = descending
        return copy
    }
    
    func limit(_ count: Int) -> Self {
        var copy = self
        copy.limitCount = count
        return copy
    }
    
    func `where`(_ predicate: @escaping (Record) -> Bool) -> Self {
        var copy = self
        copy.predicate = predicate
        return copy
    }
    
    func all() throws -> [Record] {
        // Build query using BlazeDB's fluent API
        var builder = client.query().where("_type", equals: .string(typeName))
        
        if let orderField = orderField {
            builder = builder.orderBy(orderField, descending: orderDescending)
        }
        
        // Execute query - BlazeDB owns query execution
        let result = try builder.execute()
        let blazeRecords = try result.records
        
        // Convert BlazeDataRecord back to Codable Record
        var records = try blazeRecords.map { try blazeDataRecordToRecord($0) }
        
        // Apply predicate if provided (in-memory filter for complex predicates)
        // BlazeDB owns query execution, but we apply application-level predicates after
        if let predicate = predicate {
            records = records.filter(predicate)
        }
        
        // Apply limit after predicate (if limit was specified)
        if let limitCount = limitCount {
            records = Array(records.prefix(limitCount))
        }
        
        return records
    }
    
    /// Convert BlazeDataRecord back to Codable Record
    /// Uses a two-step process: BlazeDataRecord -> JSON -> Record
    private func blazeDataRecordToRecord(_ blazeRecord: BlazeDataRecord) throws -> Record {
        // Step 1: Convert BlazeDataRecord to a JSON-compatible structure
        // We'll use BlazeDataRecord's own Codable to get JSON, then restructure it
        var fieldsForJSON: [String: BlazeDocumentField] = [:]
        for (key, field) in blazeRecord.storage {
            if key == "_type" { continue }
            fieldsForJSON[key] = field
        }
        let recordForEncoding = BlazeDataRecord(fieldsForJSON)
        
        // Step 2: Encode BlazeDataRecord to JSON
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(recordForEncoding)
        
        // Step 3: Parse JSON to extract the storage dictionary
        guard let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let storageDict = jsonDict["storage"] as? [String: Any] else {
            throw StorageError.encodingFailed
        }
        
        // Step 4: Convert storage dict (BlazeDocumentField format) to plain values
        var plainDict: [String: Any] = [:]
        for (key, value) in storageDict {
            // Value is a BlazeDocumentField encoded as JSON dict like {"bool": true}
            plainDict[key] = try extractPlainValueFromBlazeFieldJSON(value)
        }
        
        // Step 5: Encode plain dict to JSON and decode as Record
        // Use JSONEncoder (not JSONSerialization) to preserve Bool types
        // We need to convert [String: Any] to a Codable structure first
        let jsonString = try dictToJSONString(plainDict)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw StorageError.encodingFailed
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Record.self, from: jsonData)
    }
    
    /// Convert dictionary to JSON string, preserving Bool types as "true"/"false" not numbers
    private func dictToJSONString(_ dict: [String: Any]) throws -> String {
        var parts: [String] = []
        for (key, value) in dict {
            let jsonKey = escapeJSONString(key)
            let jsonValue = try valueToJSONString(value)
            parts.append("\(jsonKey):\(jsonValue)")
        }
        return "{\(parts.joined(separator: ","))}"
    }
    
    /// Convert Any value to JSON string representation, preserving types
    private func valueToJSONString(_ value: Any) throws -> String {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"  // JSON bool literal
        case let str as String:
            return escapeJSONString(str)
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let uuid as UUID:
            return "\"\(uuid.uuidString)\""
        case let array as [Any]:
            let items = try array.map { try valueToJSONString($0) }
            return "[\(items.joined(separator: ","))]"
        case let dict as [String: Any]:
            return try dictToJSONString(dict)
        case is NSNull:
            return "null"
        default:
            // Handle NSNumber (which might be a bridged Bool)
            if let nsNumber = value as? NSNumber {
                if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                    return nsNumber.boolValue ? "true" : "false"
                } else if nsNumber.objCType.pointee == 0x64 { // 'd' for double
                    return String(nsNumber.doubleValue)
                } else {
                    return String(nsNumber.intValue)
                }
            }
            throw StorageError.unsupportedType(String(describing: type(of: value)))
        }
    }
    
    /// Escape string for JSON
    private func escapeJSONString(_ str: String) -> String {
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
    
    /// Extract plain value from BlazeDocumentField JSON representation
    /// BlazeDocumentField encodes as single-key dict: {"bool": true}, {"string": "value"}, etc.
    /// Note: JSONSerialization converts Bools to NSNumber, so we must handle that
    private func extractPlainValueFromBlazeFieldJSON(_ value: Any) throws -> Any {
        guard let fieldDict = value as? [String: Any] else {
            return value
        }
        
        // Check each possible BlazeDocumentField type
        // Handle bool: JSONSerialization converts true/false to NSNumber (__NSCFBoolean)
        if fieldDict["bool"] != nil {
            let boolValue = fieldDict["bool"]!
            // Check if it's already a Bool, or if it's an NSNumber representing a boolean
            if let bool = boolValue as? Bool {
                return bool
            } else if let nsNumber = boolValue as? NSNumber, CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                return nsNumber.boolValue  // Convert NSNumber boolean back to Bool
            }
        }
        
        if let stringValue = fieldDict["string"] as? String {
            return stringValue
        } else if let intValue = fieldDict["int"] as? Int {
            return intValue
        } else if let doubleValue = fieldDict["double"] as? Double {
            return doubleValue
        } else if let uuidString = fieldDict["uuid"] as? String {
            return uuidString  // UUID as string for JSON
        } else if let dateString = fieldDict["date"] as? String {
            return dateString  // Date as ISO8601 string
        } else if let dataString = fieldDict["data"] as? String {
            return dataString  // Data as base64 string
        } else if let arrayValue = fieldDict["array"] as? [Any] {
            return try arrayValue.map { try extractPlainValueFromBlazeFieldJSON($0) }
        } else if let dictValue = fieldDict["dictionary"] as? [String: Any] {
            var result: [String: Any] = [:]
            for (k, v) in dictValue {
                result[k] = try extractPlainValueFromBlazeFieldJSON(v)
            }
            return result
        } else if fieldDict["null"] != nil {
            return NSNull()
        }
        
        // Fallback: return as-is if not a recognized BlazeDocumentField format
        return value
    }
    
    /// Extract field name from KeyPath string representation
    /// Simplified: assumes format like "\\.fieldName" or "fieldName"
    private func extractFieldName(from keyPathString: String) -> String {
        // KeyPath string format: "\\<TypeName>.<fieldName>"
        // We want just the field name
        if let lastDot = keyPathString.lastIndex(of: ".") {
            let afterDot = keyPathString.index(after: lastDot)
            return String(keyPathString[afterDot...])
        }
        return keyPathString
    }
}

enum StorageError: Error, CustomStringConvertible {
    case encodingFailed
    case unsupportedType(String)
    
    var description: String {
        switch self {
        case .encodingFailed:
            return "Failed to encode record to BlazeDataRecord"
        case .unsupportedType(let type):
            return "Unsupported type for BlazeDB storage: \(type)"
        }
    }
}
