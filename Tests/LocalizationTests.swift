import XCTest
@testable import Double_Bubble

/// The string catalogue, checked against the source that uses it.
///
/// Both of these exist because both have already shipped.
///
/// `L()` takes a `String.LocalizationValue`, and Xcode's extractor does not
/// look inside a wrapper — so `-exportLocalizations` only ever re-emits what
/// the catalogue already holds, and a new string reaches the interface in
/// English no matter which language is chosen. The Overview screen went out
/// half-translated that way.
///
/// The second is worse than cosmetic. A translation that reorders `%lld` and
/// `%@` without positional specifiers feeds an integer to `%@` and the app
/// dies on the spot — "Аккаунтов «%@»: %lld" against "%lld accounts of %@" was
/// a real crash, found by a segfault rather than by anything reading it.
final class LocalizationTests: XCTestCase {

    // MARK: Fixtures

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo

    private static let sources = URL(fileURLWithPath: "DoubleBubble", relativeTo: root)

    private static let catalogue: [String: Any] = {
        let url = sources.appendingPathComponent("Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any] else { return [:] }
        return strings
    }()

    private static let swiftFiles: [URL] = {
        guard let walker = FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }()

    // MARK: Every key the source asks for is in the catalogue

    func testCatalogueWasFound() {
        XCTAssertFalse(Self.catalogue.isEmpty, "Localizable.xcstrings not readable at \(Self.root.path)")
        XCTAssertFalse(Self.swiftFiles.isEmpty, "no Swift sources found to scan")
    }

    func testEveryPlainStringIsInTheCatalogue() {
        var missing: [String] = []
        for file in Self.swiftFiles {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for call in Self.localizedCalls(in: source) where call.isPlain {
                let key = call.key
                if !key.isEmpty, Self.catalogue[key] == nil { missing.append(key) }
            }
        }
        XCTAssertEqual(missing.sorted(), [], "these reach the interface untranslated")
    }

    /// An interpolated string becomes a key with format specifiers in it, and
    /// which specifier depends on the Swift type — so this checks that *some*
    /// key matches the literal parts, which is the failure that actually
    /// happens: the string was never added at all.
    func testEveryInterpolatedStringHasAMatchingKey() {
        let keys = Array(Self.catalogue.keys)
        var missing: [String] = []
        for file in Self.swiftFiles {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for call in Self.localizedCalls(in: source) where !call.isPlain {
                guard let regex = try? NSRegularExpression(
                    pattern: call.pattern, options: [.dotMatchesLineSeparators]) else { continue }
                let matched = keys.contains { key in
                    regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
                }
                if !matched { missing.append(call.described) }
            }
        }
        XCTAssertEqual(missing.sorted(), [], "these reach the interface untranslated")
    }

    // MARK: Translations cannot reorder specifiers without saying so

    func testTranslationsKeepTheirFormatSpecifiers() {
        var broken: [String] = []
        for (key, entry) in Self.catalogue {
            let source = Self.specifiers(in: key)
            guard !source.isEmpty else { continue }
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }

            for (language, value) in localizations {
                guard let value = value as? [String: Any],
                      let unit = value["stringUnit"] as? [String: Any],
                      let translation = unit["value"] as? String else { continue }
                let theirs = Self.specifiers(in: translation)

                if theirs.contains(where: { $0.position != nil }) {
                    // Positional: every one has to point at a source argument
                    // of its own type.
                    guard theirs.allSatisfy({ $0.position != nil }) else {
                        broken.append("\(language): «\(key)» mixes positional and plain specifiers")
                        continue
                    }
                    for specifier in theirs {
                        guard let position = specifier.position, position >= 1, position <= source.count else {
                            broken.append("\(language): «\(key)» refers to argument \(specifier.position ?? 0), which does not exist")
                            continue
                        }
                        if source[position - 1].kind != specifier.kind {
                            broken.append("\(language): «\(key)» reads argument \(position) as \(specifier.kind), but it is \(source[position - 1].kind)")
                        }
                    }
                } else if theirs.map(\.kind) != source.map(\.kind) {
                    // Plain specifiers are positional by their order, so any
                    // difference is an argument read as the wrong type — the
                    // crash this test exists for.
                    broken.append(
                        "\(language): «\(key)» takes \(source.map(\.kind)) but the translation takes \(theirs.map(\.kind)); reorder with %1$…, %2$…")
                }
            }
        }
        XCTAssertEqual(broken.sorted(), [], "a translation reads an argument as the wrong type")
    }

    func testEveryKeyIsTranslatedIntoRussian() {
        var untranslated: [String] = []
        for (key, entry) in Self.catalogue {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  localizations["ru"] != nil else {
                // A key that is only a specifier — "%@" — is a pass-through
                // with nothing to translate.
                if key.trimmingCharacters(in: CharacterSet(charactersIn: "%@ldiu$/1234567890")).isEmpty { continue }
                untranslated.append(key)
                continue
            }
        }
        XCTAssertEqual(untranslated.sorted(), [], "these fall back to English in a Russian interface")
    }

    // MARK: Scanning

    /// A literal in the order it was written, so an interpolation at either
    /// end is not lost — `L("Open \(name)")` has to become `^Open .+$`, and
    /// keeping only the literal parts made it `^Open $`.
    private enum Part: Equatable {
        case literal(String)
        case interpolation
    }

    private struct Call {
        var parts: [Part]

        var isPlain: Bool { !parts.contains(.interpolation) }

        var key: String {
            parts.compactMap { if case .literal(let text) = $0 { return text } else { return nil } }
                .joined()
        }

        /// A regular expression matching any catalogue key of this shape.
        var pattern: String {
            "^" + parts.map {
                switch $0 {
                case .literal(let text): return NSRegularExpression.escapedPattern(for: text)
                case .interpolation: return ".+"
                }
            }.joined() + "$"
        }

        var described: String {
            parts.map {
                switch $0 {
                case .literal(let text): return text
                case .interpolation: return "…"
                }
            }.joined()
        }
    }

    /// Finds `L("…")` and returns its literal parts, with interpolations
    /// counted rather than reconstructed.
    private static func localizedCalls(in source: String) -> [Call] {
        var calls: [Call] = []
        let characters = Array(source)
        var index = 0

        while index < characters.count {
            guard characters[index] == "L",
                  index + 1 < characters.count,
                  characters[index + 1] == "(",
                  index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber
                                  || characters[index - 1] == "_" || characters[index - 1] == ".") else {
                index += 1
                continue
            }
            var cursor = index + 2
            while cursor < characters.count, characters[cursor] == " " { cursor += 1 }
            guard cursor < characters.count, characters[cursor] == "\"" else {
                index += 1
                continue
            }
            if let call = scanLiteral(characters, from: cursor, end: &cursor) {
                calls.append(call)
                index = cursor
            } else {
                index += 1
            }
        }
        return calls
    }

    /// Reads one Swift string literal, stepping over escapes and skipping the
    /// balanced parentheses of an interpolation.
    private static func scanLiteral(_ characters: [Character], from start: Int, end: inout Int) -> Call? {
        var parts: [Part] = []
        var buffer = ""
        var index = start + 1

        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                let next = characters[index + 1]
                if next == "(" {
                    if !buffer.isEmpty { parts.append(.literal(buffer)); buffer = "" }
                    parts.append(.interpolation)
                    var depth = 1
                    index += 2
                    while index < characters.count, depth > 0 {
                        if characters[index] == "(" { depth += 1 }
                        if characters[index] == ")" { depth -= 1 }
                        index += 1
                    }
                    continue
                }
                switch next {
                case "n": buffer.append("\n")
                case "t": buffer.append("\t")
                case "\"": buffer.append("\"")
                case "\\": buffer.append("\\")
                default: buffer.append(next)
                }
                index += 2
                continue
            }
            if character == "\"" {
                if !buffer.isEmpty { parts.append(.literal(buffer)) }
                end = index + 1
                return Call(parts: parts)
            }
            buffer.append(character)
            index += 1
        }
        return nil
    }

    private struct Specifier { var position: Int?; var kind: String }

    private static func specifiers(in string: String) -> [Specifier] {
        let pattern = "%(?:(\\d+)\\$)?[-+ #0]*[0-9.*]*(hh|h|ll|l|q|L|z|t|j)?([@diouxXeEfgGaAcsSpn%])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            let conversion = Range(match.range(at: 3), in: string).map { String(string[$0]) } ?? ""
            guard conversion != "%" else { return nil }   // an escaped percent sign
            let length = Range(match.range(at: 2), in: string).map { String(string[$0]) } ?? ""
            let position = Range(match.range(at: 1), in: string).flatMap { Int(string[$0]) }
            return Specifier(position: position, kind: length + conversion)
        }
    }
}
