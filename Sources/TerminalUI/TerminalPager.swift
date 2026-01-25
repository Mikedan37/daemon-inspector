//
//  TerminalPager.swift
//  daemon-inspector
//
//  Built-in scrollable pager for terminal output
//  No external dependencies, uses ANSI escape codes
//

import Foundation

/// A minimal, built-in terminal pager
/// Supports scrolling, paging, and quitting
/// No external dependencies required
public final class TerminalPager {
    
    // MARK: - Properties
    
    private let lines: [String]
    private var topLine: Int = 0
    private var terminalRows: Int
    private var terminalCols: Int
    private var originalTermios: termios?
    private var isRunning = false
    
    /// Status bar height (1 line at bottom)
    private let statusBarHeight = 1
    
    /// Visible content rows (terminal rows minus status bar)
    private var visibleRows: Int {
        max(1, terminalRows - statusBarHeight)
    }
    
    // MARK: - Initialization
    
    public init(content: String) {
        self.lines = content.components(separatedBy: "\n")
        let size = TTYDetector.terminalSize
        self.terminalRows = size.rows
        self.terminalCols = size.cols
    }
    
    public init(lines: [String]) {
        self.lines = lines
        let size = TTYDetector.terminalSize
        self.terminalRows = size.rows
        self.terminalCols = size.cols
    }
    
    // MARK: - Public API
    
    /// Run the pager interactively
    /// Blocks until user quits
    public func run() {
        guard TTYDetector.isInteractive else {
            // Not a TTY, just print everything
            for line in lines {
                print(line)
            }
            return
        }
        
        enableRawMode()
        defer { disableRawMode() }
        
        hideCursor()
        defer { showCursor() }
        
        isRunning = true
        render()
        
        while isRunning {
            if let key = readKey() {
                handleKey(key)
            }
        }
        
        // Clear screen on exit
        clearScreen()
    }
    
    // MARK: - Terminal Control
    
    private func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw
        
        // Disable canonical mode and echo
        raw.c_lflag &= ~UInt(ICANON | ECHO)
        
        // Set minimum characters and timeout
        raw.c_cc.16 = 1  // VMIN
        raw.c_cc.17 = 0  // VTIME
        
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }
    
    private func disableRawMode() {
        if var original = originalTermios {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
    }
    
    private func hideCursor() {
        print("\u{001B}[?25l", terminator: "")
        fflush(stdout)
    }
    
    private func showCursor() {
        print("\u{001B}[?25h", terminator: "")
        fflush(stdout)
    }
    
    private func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }
    
    private func moveCursor(row: Int, col: Int) {
        print("\u{001B}[\(row);\(col)H", terminator: "")
    }
    
    private func clearLine() {
        print("\u{001B}[2K", terminator: "")
    }
    
    // MARK: - Rendering
    
    private func render() {
        // Move to top-left
        moveCursor(row: 1, col: 1)
        
        // Render visible lines
        for i in 0..<visibleRows {
            clearLine()
            let lineIndex = topLine + i
            if lineIndex < lines.count {
                let line = truncate(lines[lineIndex], to: terminalCols)
                print(line)
            } else {
                print("~")  // Empty line indicator
            }
        }
        
        // Render status bar
        renderStatusBar()
        
        fflush(stdout)
    }
    
    private func renderStatusBar() {
        moveCursor(row: terminalRows, col: 1)
        clearLine()
        
        // Invert colors for status bar
        let invertOn = "\u{001B}[7m"
        let invertOff = "\u{001B}[0m"
        
        // Clearer position indicator
        let startLine = topLine + 1
        let endLine = min(topLine + visibleRows, lines.count)
        let position = "Lines \(startLine)–\(endLine) of \(lines.count)"
        
        // More descriptive controls
        let help = "j/k scroll · space page · g/G jump · q quit"
        
        // Center the separator
        let separator = " │ "
        let contentLength = position.count + separator.count + help.count
        let padding = max(0, terminalCols - contentLength - 2)
        let leftPad = padding / 2
        let rightPad = padding - leftPad
        
        let statusText = " \(String(repeating: " ", count: leftPad))\(position)\(separator)\(help)\(String(repeating: " ", count: rightPad)) "
        
        print("\(invertOn)\(truncate(statusText, to: terminalCols))\(invertOff)", terminator: "")
    }
    
    private func truncate(_ str: String, to maxWidth: Int) -> String {
        if str.count <= maxWidth {
            return str
        }
        let endIndex = str.index(str.startIndex, offsetBy: max(0, maxWidth - 1))
        return String(str[..<endIndex]) + "…"
    }
    
    // MARK: - Input Handling
    
    private enum Key {
        case up
        case down
        case pageUp
        case pageDown
        case home
        case end
        case quit
        case unknown
    }
    
    private func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 3)
        let bytesRead = read(STDIN_FILENO, &buffer, 3)
        
        guard bytesRead > 0 else { return nil }
        
        // Single character
        if bytesRead == 1 {
            switch buffer[0] {
            case 0x71: return .quit      // q
            case 0x6A: return .down      // j
            case 0x6B: return .up        // k
            case 0x67: return .home      // g
            case 0x47: return .end       // G
            case 0x20: return .pageDown  // space
            case 0x62: return .pageUp    // b
            default: return .unknown
            }
        }
        
        // Escape sequences
        if bytesRead == 3 && buffer[0] == 0x1B && buffer[1] == 0x5B {
            switch buffer[2] {
            case 0x41: return .up        // Arrow up
            case 0x42: return .down      // Arrow down
            case 0x35: return .pageUp    // Page up (ESC [ 5 ~)
            case 0x36: return .pageDown  // Page down (ESC [ 6 ~)
            default: return .unknown
            }
        }
        
        return .unknown
    }
    
    private func handleKey(_ key: Key) {
        let oldTop = topLine
        
        switch key {
        case .quit:
            isRunning = false
            
        case .down:
            scrollDown(by: 1)
            
        case .up:
            scrollUp(by: 1)
            
        case .pageDown:
            scrollDown(by: visibleRows - 1)
            
        case .pageUp:
            scrollUp(by: visibleRows - 1)
            
        case .home:
            topLine = 0
            
        case .end:
            topLine = max(0, lines.count - visibleRows)
            
        case .unknown:
            break
        }
        
        // Only re-render if position changed
        if topLine != oldTop {
            render()
        }
    }
    
    private func scrollDown(by amount: Int) {
        let maxTop = max(0, lines.count - visibleRows)
        topLine = min(maxTop, topLine + amount)
    }
    
    private func scrollUp(by amount: Int) {
        topLine = max(0, topLine - amount)
    }
}
