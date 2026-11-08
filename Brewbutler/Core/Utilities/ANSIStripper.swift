import Foundation

/// Removes ANSI CSI/OSC sequences and stray control characters from brew output.
/// Log rendering and text parsing both go through this so a colour switch in brew
/// can never poison JSON/line parsing.
public enum ANSIStripper {
    public static func strip(_ input: String) -> String {
        guard input.contains("\u{001B}") || input.contains("\u{0008}") else {
            return input.replacingOccurrences(of: "\u{0000}", with: "")
        }
        var output = String()
        output.reserveCapacity(input.count)

        let scalars = Array(input.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar.value == 0x1B else {
                if scalar.value == 0x08 {
                    if !output.isEmpty { output.removeLast() }
                } else if scalar.value == 0x0D || scalar.value == 0x0A || scalar.value == 0x09 || scalar.value >= 0x20 {
                    output.unicodeScalars.append(scalar)
                }
                index += 1
                continue
            }

            // ESC sequence
            index += 1
            guard index < scalars.count else { break }
            let next = scalars[index]

            if next == "[" {
                // CSI: ESC [ parameters intermediates final-byte
                index += 1
                while index < scalars.count {
                    let value = scalars[index].value
                    if value >= 0x40 && value <= 0x7E { // final byte
                        index += 1
                        break
                    }
                    index += 1
                }
            } else if next == "]" {
                // OSC: terminated by BEL or ESC backslash
                index += 1
                while index < scalars.count {
                    if scalars[index].value == 0x07 {
                        index += 1
                        break
                    }
                    if scalars[index].value == 0x1B, index + 1 < scalars.count, scalars[index + 1] == "\\" {
                        index += 2
                        break
                    }
                    index += 1
                }
            } else if next == "P" || next == "^" || next == "_" || next == "X" {
                // DCS / PM / APC / SOS, terminated by ST
                index += 1
                while index < scalars.count {
                    if scalars[index].value == 0x1B, index + 1 < scalars.count, scalars[index + 1] == "\\" {
                        index += 2
                        break
                    }
                    index += 1
                }
            } else if next == "(" || next == ")" || next == "*" || next == "+" {
                index += 2
            } else {
                index += 1
            }
        }
        return output
    }
}
