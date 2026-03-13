import Foundation
import Combine

/// Terminal emulator that manages output buffer, scrollback, and ANSI parsing
class TerminalEmulator: ObservableObject {
    @Published var lines: [TerminalLine] = []
    @Published var cursorPosition: Int = 0

    private let maxScrollback = 5000
    private let ansiParser = ANSIParser()

    struct TerminalLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType

        enum LineType {
            case input      // User-typed command
            case output     // Command output
            case error      // Error output
            case prompt     // Shell prompt
            case system     // System messages
        }
    }

    func addPrompt(_ prompt: String) {
        lines.append(TerminalLine(text: prompt, type: .prompt))
        trimScrollback()
    }

    func addInput(_ input: String) {
        lines.append(TerminalLine(text: input, type: .input))
        trimScrollback()
    }

    func addOutput(_ text: String) {
        // Split into lines and add each
        let outputLines = text.components(separatedBy: "\n")
        for line in outputLines {
            if !line.isEmpty {
                let parsed = ansiParser.stripANSI(line)
                lines.append(TerminalLine(text: parsed, type: .output))
            }
        }
        trimScrollback()
    }

    func addError(_ text: String) {
        lines.append(TerminalLine(text: text, type: .error))
        trimScrollback()
    }

    func addSystem(_ text: String) {
        lines.append(TerminalLine(text: text, type: .system))
        trimScrollback()
    }

    func clear() {
        lines.removeAll()
    }

    private func trimScrollback() {
        if lines.count > maxScrollback {
            lines.removeFirst(lines.count - maxScrollback)
        }
    }
}

/// Minimal ANSI escape code parser
class ANSIParser {
    /// Strip ANSI escape sequences from text
    func stripANSI(_ text: String) -> String {
        // Remove CSI sequences: ESC [ ... final_byte
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\u{1B}" {
                // Skip ESC
                i = text.index(after: i)
                if i < text.endIndex && text[i] == "[" {
                    // Skip CSI sequence until final byte (0x40-0x7E)
                    i = text.index(after: i)
                    while i < text.endIndex {
                        let c = text[i]
                        i = text.index(after: i)
                        if c >= "@" && c <= "~" { break }
                    }
                }
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }
        return result
    }
}
