//
//  TTYDetector.swift
//  daemon-inspector
//
//  TTY detection for interactive vs piped output
//

import Foundation

/// Detects terminal capabilities and output mode
public struct TTYDetector {
    
    /// Output mode based on terminal detection
    public enum OutputMode {
        case interactive  // TTY detected, can use pager
        case piped        // Not a TTY, plain text only
        case json         // JSON mode requested, no pager
    }
    
    /// Check if stdout is connected to a terminal
    public static var isInteractive: Bool {
        isatty(STDOUT_FILENO) != 0
    }
    
    /// Check if stdin is connected to a terminal (for keyboard input)
    public static var canReadInput: Bool {
        isatty(STDIN_FILENO) != 0
    }
    
    /// Get terminal size (rows, columns)
    public static var terminalSize: (rows: Int, cols: Int) {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 {
            return (Int(size.ws_row), Int(size.ws_col))
        }
        // Fallback to reasonable defaults
        return (24, 80)
    }
    
    /// Determine output mode based on flags and terminal state
    public static func detectMode(jsonRequested: Bool) -> OutputMode {
        if jsonRequested {
            return .json
        }
        if isInteractive && canReadInput {
            return .interactive
        }
        return .piped
    }
}
