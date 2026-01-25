//
//  BinaryInspector.swift
//  daemon-inspector
//
//  Read-only binary inspection.
//  Collects metadata about on-disk binaries.
//  Never executes code, never judges trust.
//

import Foundation

/// Read-only binary inspector
/// Collects file facts and platform context without interpretation
public struct BinaryInspector {
    
    public init() {}
    
    /// Inspect a binary at the given path
    /// Returns metadata about the file, never executes it
    public func inspect(label: String, path: String) -> BinaryMetadata {
        let fileManager = FileManager.default
        
        // Check existence
        guard fileManager.fileExists(atPath: path) else {
            return .missing(label: label, path: path)
        }
        
        // Get file attributes
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return BinaryMetadata(
                daemonLabel: label,
                path: path,
                exists: true,
                errorMessage: "Unable to read file attributes"
            )
        }
        
        // Extract basic facts
        let fileType = detectFileType(at: path)
        let architecture = detectArchitecture(at: path)
        let sizeBytes = attributes[.size] as? UInt64
        let ownership = extractOwnership(from: attributes)
        let permissions = extractPermissions(from: attributes)
        let (isSymlink, resolvedPath) = checkSymlink(at: path)
        let volumeType = detectVolumeType(at: path)
        let hasCodeSignature = checkCodeSignaturePresence(at: path)
        
        return BinaryMetadata(
            daemonLabel: label,
            path: path,
            exists: true,
            fileType: fileType,
            architecture: architecture,
            sizeBytes: sizeBytes,
            ownership: ownership,
            permissions: permissions,
            isSymlink: isSymlink,
            resolvedPath: resolvedPath,
            volumeType: volumeType,
            hasCodeSignature: hasCodeSignature
        )
    }
    
    // MARK: - File Type Detection
    
    private func detectFileType(at path: String) -> BinaryFileType {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return .unknown
        }
        defer { try? handle.close() }
        
        guard let data = try? handle.read(upToCount: 4), data.count >= 4 else {
            return .unknown
        }
        
        // Check for Mach-O magic numbers
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Mach-O magic numbers (little-endian and big-endian)
        let MH_MAGIC: UInt32 = 0xFEEDFACE
        let MH_CIGAM: UInt32 = 0xCEFAEDFE
        let MH_MAGIC_64: UInt32 = 0xFEEDFACF
        let MH_CIGAM_64: UInt32 = 0xCFFAEDFE
        let FAT_MAGIC: UInt32 = 0xCAFEBABE
        let FAT_CIGAM: UInt32 = 0xBEBAFECA
        
        switch magic {
        case MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64, FAT_MAGIC, FAT_CIGAM:
            return .machO
        default:
            break
        }
        
        // Check for script shebang
        if data[0] == 0x23 && data[1] == 0x21 {  // "#!"
            return .script
        }
        
        return .unknown
    }
    
    // MARK: - Architecture Detection
    
    private func detectArchitecture(at path: String) -> BinaryArchitecture {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return .unknown
        }
        defer { try? handle.close() }
        
        guard let data = try? handle.read(upToCount: 8), data.count >= 8 else {
            return .unknown
        }
        
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Fat binary (universal)
        let FAT_MAGIC: UInt32 = 0xCAFEBABE
        let FAT_CIGAM: UInt32 = 0xBEBAFECA
        
        if magic == FAT_MAGIC || magic == FAT_CIGAM {
            return .universal
        }
        
        // 64-bit Mach-O
        let MH_MAGIC_64: UInt32 = 0xFEEDFACF
        let MH_CIGAM_64: UInt32 = 0xCFFAEDFE
        
        if magic == MH_MAGIC_64 || magic == MH_CIGAM_64 {
            // Read cputype from header (offset 4)
            let cputype = data.withUnsafeBytes { ptr -> Int32 in
                ptr.load(fromByteOffset: 4, as: Int32.self)
            }
            
            // CPU_TYPE_ARM64 = 0x0100000C (16777228)
            // CPU_TYPE_X86_64 = 0x01000007 (16777223)
            let CPU_TYPE_ARM64: Int32 = 0x0100000C
            let CPU_TYPE_X86_64: Int32 = 0x01000007
            
            // Handle byte swapping
            let actualCputype = (magic == MH_CIGAM_64) ? cputype.byteSwapped : cputype
            
            switch actualCputype {
            case CPU_TYPE_ARM64:
                return .arm64
            case CPU_TYPE_X86_64:
                return .x86_64
            default:
                return .unknown
            }
        }
        
        return .unknown
    }
    
    // MARK: - Ownership Extraction
    
    private func extractOwnership(from attributes: [FileAttributeKey: Any]) -> FileOwnership? {
        guard let uid = attributes[.ownerAccountID] as? UInt32,
              let gid = attributes[.groupOwnerAccountID] as? UInt32 else {
            return nil
        }
        
        let userName = attributes[.ownerAccountName] as? String
        let groupName = attributes[.groupOwnerAccountName] as? String
        
        return FileOwnership(
            uid: uid,
            gid: gid,
            userName: userName,
            groupName: groupName
        )
    }
    
    // MARK: - Permissions Extraction
    
    private func extractPermissions(from attributes: [FileAttributeKey: Any]) -> String? {
        guard let posixPermissions = attributes[.posixPermissions] as? UInt16 else {
            return nil
        }
        
        return formatPosixPermissions(posixPermissions)
    }
    
    private func formatPosixPermissions(_ mode: UInt16) -> String {
        var result = ""
        
        // Owner
        result += (mode & 0o400) != 0 ? "r" : "-"
        result += (mode & 0o200) != 0 ? "w" : "-"
        result += (mode & 0o100) != 0 ? "x" : "-"
        
        // Group
        result += (mode & 0o040) != 0 ? "r" : "-"
        result += (mode & 0o020) != 0 ? "w" : "-"
        result += (mode & 0o010) != 0 ? "x" : "-"
        
        // Other
        result += (mode & 0o004) != 0 ? "r" : "-"
        result += (mode & 0o002) != 0 ? "w" : "-"
        result += (mode & 0o001) != 0 ? "x" : "-"
        
        return result
    }
    
    // MARK: - Symlink Handling
    
    private func checkSymlink(at path: String) -> (isSymlink: Bool, resolvedPath: String?) {
        let fileManager = FileManager.default
        
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return (false, nil)
        }
        
        let fileType = attributes[.type] as? FileAttributeType
        
        if fileType == .typeSymbolicLink {
            let resolved = try? fileManager.destinationOfSymbolicLink(atPath: path)
            return (true, resolved)
        }
        
        return (false, nil)
    }
    
    // MARK: - Volume Type Detection
    
    private func detectVolumeType(at path: String) -> VolumeType {
        // System volume paths (sealed, read-only)
        let systemPrefixes = [
            "/System/",
            "/usr/",
            "/bin/",
            "/sbin/"
        ]
        
        // Data volume paths
        let dataPrefixes = [
            "/Applications/",
            "/Library/",
            "/Users/",
            "/private/var/",
            "/var/"
        ]
        
        // External volume prefix
        let externalPrefix = "/Volumes/"
        
        for prefix in systemPrefixes {
            if path.hasPrefix(prefix) {
                return .system
            }
        }
        
        for prefix in dataPrefixes {
            if path.hasPrefix(prefix) {
                return .data
            }
        }
        
        if path.hasPrefix(externalPrefix) {
            return .external
        }
        
        return .unknown
    }
    
    // MARK: - Code Signature Presence Check
    
    private func checkCodeSignaturePresence(at path: String) -> Bool {
        // Check for presence of code signature by looking for the __LINKEDIT segment
        // and LC_CODE_SIGNATURE load command
        // This is a lightweight check - we don't validate trust
        
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return false
        }
        defer { try? handle.close() }
        
        guard let headerData = try? handle.read(upToCount: 32), headerData.count >= 32 else {
            return false
        }
        
        let magic = headerData.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Only check 64-bit Mach-O for simplicity
        let MH_MAGIC_64: UInt32 = 0xFEEDFACF
        let MH_CIGAM_64: UInt32 = 0xCFFAEDFE
        
        guard magic == MH_MAGIC_64 || magic == MH_CIGAM_64 else {
            // For fat binaries, assume signed if it's a system binary
            let FAT_MAGIC: UInt32 = 0xCAFEBABE
            let FAT_CIGAM: UInt32 = 0xBEBAFECA
            if magic == FAT_MAGIC || magic == FAT_CIGAM {
                // Fat binaries on system volume are typically signed
                return detectVolumeType(at: path) == .system
            }
            return false
        }
        
        let isSwapped = (magic == MH_CIGAM_64)
        
        // Read ncmds (number of load commands) at offset 16
        let ncmds = headerData.withUnsafeBytes { ptr -> UInt32 in
            let raw = ptr.load(fromByteOffset: 16, as: UInt32.self)
            return isSwapped ? raw.byteSwapped : raw
        }
        
        // Read sizeofcmds at offset 20
        let sizeofcmds = headerData.withUnsafeBytes { ptr -> UInt32 in
            let raw = ptr.load(fromByteOffset: 20, as: UInt32.self)
            return isSwapped ? raw.byteSwapped : raw
        }
        
        // Read load commands (after 32-byte header for 64-bit)
        guard let cmdData = try? handle.read(upToCount: Int(sizeofcmds)) else {
            return false
        }
        
        // Scan for LC_CODE_SIGNATURE (0x1D)
        let LC_CODE_SIGNATURE: UInt32 = 0x1D
        var offset = 0
        
        for _ in 0..<ncmds {
            guard offset + 8 <= cmdData.count else { break }
            
            let cmd = cmdData.withUnsafeBytes { ptr -> UInt32 in
                let raw = ptr.load(fromByteOffset: offset, as: UInt32.self)
                return isSwapped ? raw.byteSwapped : raw
            }
            
            let cmdsize = cmdData.withUnsafeBytes { ptr -> UInt32 in
                let raw = ptr.load(fromByteOffset: offset + 4, as: UInt32.self)
                return isSwapped ? raw.byteSwapped : raw
            }
            
            if cmd == LC_CODE_SIGNATURE {
                return true
            }
            
            offset += Int(cmdsize)
        }
        
        return false
    }
}
