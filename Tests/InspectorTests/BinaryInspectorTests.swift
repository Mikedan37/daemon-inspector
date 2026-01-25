//
//  BinaryInspectorTests.swift
//  daemon-inspector
//
//  Unit tests for BinaryInspector.
//  Tests file type detection, symlink handling, and metadata extraction.
//  Does NOT test protected system paths.
//

import XCTest
@testable import Inspector

final class BinaryInspectorTests: XCTestCase {
    
    var inspector: BinaryInspector!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        inspector = BinaryInspector()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Path Exists Tests
    
    func testMissingPath() {
        let result = inspector.inspect(label: "test.daemon", path: "/nonexistent/path/binary")
        
        XCTAssertEqual(result.daemonLabel, "test.daemon")
        XCTAssertEqual(result.path, "/nonexistent/path/binary")
        XCTAssertFalse(result.exists)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertTrue(result.errorMessage?.contains("no longer exists") ?? false)
    }
    
    func testExistingPath() {
        // Create a simple file
        let filePath = tempDir.appendingPathComponent("testfile")
        FileManager.default.createFile(atPath: filePath.path, contents: Data([0x00, 0x01, 0x02, 0x03]))
        
        let result = inspector.inspect(label: "test.daemon", path: filePath.path)
        
        XCTAssertEqual(result.daemonLabel, "test.daemon")
        XCTAssertTrue(result.exists)
        XCTAssertNil(result.errorMessage)
    }
    
    // MARK: - Symlink Tests
    
    func testRegularFileNotSymlink() {
        let filePath = tempDir.appendingPathComponent("regular")
        FileManager.default.createFile(atPath: filePath.path, contents: Data([0x00]))
        
        let result = inspector.inspect(label: "test.daemon", path: filePath.path)
        
        XCTAssertEqual(result.isSymlink, false)
        XCTAssertNil(result.resolvedPath)
    }
    
    func testSymlinkResolution() {
        // Create target file
        let targetPath = tempDir.appendingPathComponent("target")
        FileManager.default.createFile(atPath: targetPath.path, contents: Data([0x00]))
        
        // Create symlink
        let linkPath = tempDir.appendingPathComponent("link")
        try? FileManager.default.createSymbolicLink(at: linkPath, withDestinationURL: targetPath)
        
        let result = inspector.inspect(label: "test.daemon", path: linkPath.path)
        
        XCTAssertEqual(result.isSymlink, true)
        XCTAssertNotNil(result.resolvedPath)
    }
    
    // MARK: - File Type Detection Tests
    
    func testScriptDetection() {
        // Create a script file with shebang
        let scriptPath = tempDir.appendingPathComponent("script.sh")
        let shebang = "#!/bin/sh\necho hello\n"
        try? shebang.write(toFile: scriptPath.path, atomically: true, encoding: .utf8)
        
        let result = inspector.inspect(label: "test.daemon", path: scriptPath.path)
        
        XCTAssertEqual(result.fileType, .script)
    }
    
    func testUnknownFileType() {
        // Create a file with random content
        let filePath = tempDir.appendingPathComponent("random")
        let randomData = Data([0x12, 0x34, 0x56, 0x78])
        try? randomData.write(to: filePath)
        
        let result = inspector.inspect(label: "test.daemon", path: filePath.path)
        
        XCTAssertEqual(result.fileType, .unknown)
    }
    
    // MARK: - Ownership and Permissions Tests
    
    func testOwnershipExtraction() {
        let filePath = tempDir.appendingPathComponent("owned")
        FileManager.default.createFile(atPath: filePath.path, contents: Data([0x00]))
        
        let result = inspector.inspect(label: "test.daemon", path: filePath.path)
        
        XCTAssertNotNil(result.ownership)
        // Current user should own files in temp directory
    }
    
    func testPermissionsExtraction() {
        let filePath = tempDir.appendingPathComponent("perms")
        FileManager.default.createFile(atPath: filePath.path, contents: Data([0x00]))
        
        let result = inspector.inspect(label: "test.daemon", path: filePath.path)
        
        XCTAssertNotNil(result.permissions)
        // Should be a 9-character string like "rw-r--r--"
        XCTAssertEqual(result.permissions?.count, 9)
    }
    
    // MARK: - Volume Type Tests
    
    func testSystemVolumePath() {
        // This uses path heuristics, not actual volume queries
        let result = inspector.inspect(label: "test.daemon", path: "/usr/bin/ls")
        
        // /usr/bin/ls should exist and be detected as system volume
        if result.exists {
            XCTAssertEqual(result.volumeType, .system)
        }
    }
    
    func testDataVolumePath() {
        // Files in /Applications should be on data volume
        let result = inspector.inspect(label: "test.daemon", path: "/Applications/Safari.app/Contents/MacOS/Safari")
        
        if result.exists {
            XCTAssertEqual(result.volumeType, .data)
        }
    }
    
    // MARK: - BinaryMetadata Factory Tests
    
    func testMissingFactory() {
        let metadata = BinaryMetadata.missing(label: "test", path: "/foo")
        
        XCTAssertEqual(metadata.daemonLabel, "test")
        XCTAssertEqual(metadata.path, "/foo")
        XCTAssertFalse(metadata.exists)
        XCTAssertNotNil(metadata.errorMessage)
    }
    
    func testUnknownPathFactory() {
        let metadata = BinaryMetadata.unknownPath(label: "test")
        
        XCTAssertEqual(metadata.daemonLabel, "test")
        XCTAssertFalse(metadata.exists)
        XCTAssertNotNil(metadata.errorMessage)
        XCTAssertTrue(metadata.errorMessage?.contains("not exposed") ?? false)
    }
    
    // MARK: - JSON Stability Tests
    
    func testBinaryFileTypeCodable() {
        let types: [BinaryFileType] = [.machO, .script, .unknown]
        
        for type in types {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            
            let data = try? encoder.encode(type)
            XCTAssertNotNil(data)
            
            let decoded = try? decoder.decode(BinaryFileType.self, from: data!)
            XCTAssertEqual(decoded, type)
        }
    }
    
    func testArchitectureCodable() {
        let archs: [BinaryArchitecture] = [.arm64, .x86_64, .universal, .unknown]
        
        for arch in archs {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            
            let data = try? encoder.encode(arch)
            XCTAssertNotNil(data)
            
            let decoded = try? decoder.decode(BinaryArchitecture.self, from: data!)
            XCTAssertEqual(decoded, arch)
        }
    }
    
    func testVolumeTypeCodable() {
        let volumes: [VolumeType] = [.system, .data, .external, .unknown]
        
        for volume in volumes {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            
            let data = try? encoder.encode(volume)
            XCTAssertNotNil(data)
            
            let decoded = try? decoder.decode(VolumeType.self, from: data!)
            XCTAssertEqual(decoded, volume)
        }
    }
}
