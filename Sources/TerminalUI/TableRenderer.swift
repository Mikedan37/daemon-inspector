//
//  TableRenderer.swift
//  daemon-inspector
//
//  Tabular view renderer for daemon lists
//  No aggregation, no derived meaning, just presentation
//

import Foundation
import Model

/// Renders daemon data in tabular format
/// One row per daemon, fixed columns
public struct TableRenderer {
    
    // MARK: - Column Configuration
    
    private struct Column {
        let header: String
        let minWidth: Int
        let maxWidth: Int
        let align: Alignment
        
        enum Alignment {
            case left
            case right
            case center
        }
    }
    
    private static let columns: [Column] = [
        Column(header: "Label", minWidth: 20, maxWidth: 50, align: .left),
        Column(header: "Domain", minWidth: 8, maxWidth: 12, align: .left),
        Column(header: "Status", minWidth: 7, maxWidth: 11, align: .left),
        Column(header: "PID", minWidth: 5, maxWidth: 8, align: .right),
        Column(header: "Binary", minWidth: 10, maxWidth: 40, align: .left)
    ]
    
    // MARK: - Public API
    
    /// Render daemons as a table
    /// Returns array of lines (header + separator + data rows)
    public static func render(daemons: [ObservedDaemon], terminalWidth: Int? = nil) -> [String] {
        let width = terminalWidth ?? TTYDetector.terminalSize.cols
        let columnWidths = calculateColumnWidths(for: daemons, totalWidth: width)
        
        var lines: [String] = []
        
        // Header row
        lines.append(renderHeaderRow(widths: columnWidths))
        
        // Separator
        lines.append(renderSeparator(widths: columnWidths))
        
        // Data rows
        for daemon in daemons.sorted(by: { $0.label < $1.label }) {
            lines.append(renderDataRow(daemon: daemon, widths: columnWidths))
        }
        
        // Phase 4: Unknown field explanations (footnotes)
        let hasUnknownDomain = daemons.contains { $0.domain == "unknown" }
        let hasMissingBinary = daemons.contains { $0.binaryPath == nil }
        let hasMissingPID = daemons.contains { $0.pid == nil }
        
        if hasUnknownDomain || hasMissingBinary || hasMissingPID {
            lines.append("")
            lines.append("Legend:")
            if hasMissingPID {
                lines.append("  PID: -          = Not currently running")
            }
            if hasMissingBinary {
                lines.append("  Binary: -       = Not exposed by launchd")
            }
            if hasUnknownDomain {
                lines.append("  Domain: unknown = No domain metadata available")
            }
        }
        
        return lines
    }
    
    // MARK: - Column Width Calculation
    
    private static func calculateColumnWidths(for daemons: [ObservedDaemon], totalWidth: Int) -> [Int] {
        // Start with minimum widths
        var widths = columns.map { $0.minWidth }
        
        // Calculate content widths
        let contentWidths = columns.enumerated().map { (i, col) -> Int in
            let maxContent = daemons.reduce(col.header.count) { maxLen, daemon in
                max(maxLen, getColumnValue(daemon: daemon, columnIndex: i).count)
            }
            return min(maxContent, col.maxWidth)
        }
        
        // Use content widths where they fit
        for i in 0..<widths.count {
            widths[i] = max(widths[i], min(contentWidths[i], columns[i].maxWidth))
        }
        
        // Calculate total and adjust if needed
        let separators = columns.count + 1  // | before each column + | at end
        let totalUsed = widths.reduce(0, +) + separators + (columns.count * 2)  // 2 spaces padding per column
        
        if totalUsed > totalWidth {
            // Shrink columns proportionally, respecting minimums
            let excess = totalUsed - totalWidth
            let shrinkable = widths.enumerated().reduce(0) { sum, pair in
                sum + max(0, pair.element - columns[pair.offset].minWidth)
            }
            
            if shrinkable > 0 {
                var remaining = excess
                for i in 0..<widths.count {
                    let canShrink = widths[i] - columns[i].minWidth
                    if canShrink > 0 {
                        let shrinkAmount = min(canShrink, remaining * canShrink / shrinkable)
                        widths[i] -= shrinkAmount
                        remaining -= shrinkAmount
                    }
                }
            }
        }
        
        return widths
    }
    
    // MARK: - Row Rendering
    
    private static func renderHeaderRow(widths: [Int]) -> String {
        var parts: [String] = []
        for (i, col) in columns.enumerated() {
            parts.append(pad(col.header, to: widths[i], align: .center))
        }
        return "| " + parts.joined(separator: " | ") + " |"
    }
    
    private static func renderSeparator(widths: [Int]) -> String {
        let dashes = widths.map { String(repeating: "-", count: $0) }
        return "|-" + dashes.joined(separator: "-|-") + "-|"
    }
    
    private static func renderDataRow(daemon: ObservedDaemon, widths: [Int]) -> String {
        var parts: [String] = []
        for (i, col) in columns.enumerated() {
            let value = getColumnValue(daemon: daemon, columnIndex: i)
            parts.append(pad(truncate(value, to: widths[i]), to: widths[i], align: col.align))
        }
        return "| " + parts.joined(separator: " | ") + " |"
    }
    
    // MARK: - Value Extraction
    
    private static func getColumnValue(daemon: ObservedDaemon, columnIndex: Int) -> String {
        switch columnIndex {
        case 0: return daemon.label
        case 1: return formatDomain(daemon.domain)
        case 2: return daemon.isRunning ? "running" : "stopped"
        case 3: return daemon.pid.map { String($0) } ?? "-"
        case 4: return daemon.binaryPath ?? "-"
        default: return ""
        }
    }
    
    private static func formatDomain(_ domain: String) -> String {
        // Shorten gui/XXX to gui
        if domain.hasPrefix("gui/") {
            return "gui"
        }
        return domain
    }
    
    // MARK: - String Utilities
    
    private static func truncate(_ str: String, to maxWidth: Int) -> String {
        if str.count <= maxWidth {
            return str
        }
        let endIndex = str.index(str.startIndex, offsetBy: max(0, maxWidth - 1))
        return String(str[..<endIndex]) + "…"
    }
    
    private static func pad(_ str: String, to width: Int, align: Column.Alignment) -> String {
        let padding = max(0, width - str.count)
        
        switch align {
        case .left:
            return str + String(repeating: " ", count: padding)
        case .right:
            return String(repeating: " ", count: padding) + str
        case .center:
            let left = padding / 2
            let right = padding - left
            return String(repeating: " ", count: left) + str + String(repeating: " ", count: right)
        }
    }
}
