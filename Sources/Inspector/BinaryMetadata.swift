//
//  BinaryMetadata.swift
//  daemon-inspector
//
//  Read-only metadata about a daemon's binary file.
//  No interpretation, no trust judgment, facts only.
//

import Foundation

/// Binary file type detection
public enum BinaryFileType: String, Codable {
    case machO = "mach-o"
    case script = "script"
    case unknown = "unknown"
}

/// CPU architecture for Mach-O binaries
public enum BinaryArchitecture: String, Codable {
    case arm64 = "arm64"
    case x86_64 = "x86_64"
    case universal = "universal"
    case unknown = "unknown"
}

/// Volume type where binary resides
public enum VolumeType: String, Codable {
    case system = "system"   // Sealed system volume
    case data = "data"       // Data volume
    case external = "external"
    case unknown = "unknown"
}

/// File ownership information
public struct FileOwnership: Codable {
    public let uid: UInt32
    public let gid: UInt32
    public let userName: String?
    public let groupName: String?
    
    public init(uid: UInt32, gid: UInt32, userName: String?, groupName: String?) {
        self.uid = uid
        self.gid = gid
        self.userName = userName
        self.groupName = groupName
    }
}

/// Complete binary metadata
/// All facts, no interpretation
public struct BinaryMetadata {
    // Identity
    public let daemonLabel: String
    public let path: String
    
    // Existence
    public let exists: Bool
    
    // File facts (nil if file doesn't exist)
    public let fileType: BinaryFileType?
    public let architecture: BinaryArchitecture?
    public let sizeBytes: UInt64?
    public let ownership: FileOwnership?
    public let permissions: String?  // e.g., "r-xr-xr-x"
    
    // Symlink handling
    public let isSymlink: Bool?
    public let resolvedPath: String?  // nil if not a symlink or can't resolve
    
    // Platform context
    public let volumeType: VolumeType?
    public let hasCodeSignature: Bool?  // presence only, no trust judgment
    
    // Error case
    public let errorMessage: String?
    
    public init(
        daemonLabel: String,
        path: String,
        exists: Bool,
        fileType: BinaryFileType? = nil,
        architecture: BinaryArchitecture? = nil,
        sizeBytes: UInt64? = nil,
        ownership: FileOwnership? = nil,
        permissions: String? = nil,
        isSymlink: Bool? = nil,
        resolvedPath: String? = nil,
        volumeType: VolumeType? = nil,
        hasCodeSignature: Bool? = nil,
        errorMessage: String? = nil
    ) {
        self.daemonLabel = daemonLabel
        self.path = path
        self.exists = exists
        self.fileType = fileType
        self.architecture = architecture
        self.sizeBytes = sizeBytes
        self.ownership = ownership
        self.permissions = permissions
        self.isSymlink = isSymlink
        self.resolvedPath = resolvedPath
        self.volumeType = volumeType
        self.hasCodeSignature = hasCodeSignature
        self.errorMessage = errorMessage
    }
    
    /// Create metadata for a missing or unknown binary
    public static func missing(label: String, path: String) -> BinaryMetadata {
        BinaryMetadata(
            daemonLabel: label,
            path: path,
            exists: false,
            errorMessage: "Binary path no longer exists on disk"
        )
    }
    
    /// Create metadata for an unknown binary path
    public static func unknownPath(label: String) -> BinaryMetadata {
        BinaryMetadata(
            daemonLabel: label,
            path: "(unknown)",
            exists: false,
            errorMessage: "Binary path not exposed by launchd for this daemon"
        )
    }
}
