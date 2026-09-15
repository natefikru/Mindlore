import Foundation

// Pulls the JSON object out of a model response. Strict-schema responses are already clean;
// JSON-mode and prompt-only responses sometimes wrap it in code fences or prose.
nonisolated enum StructuredOutputParser {
    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = jsonObjectData(in: text) else { throw AIError.invalidResponse }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // DecodingError descriptions can quote response values, so only the case survives.
            throw AIError.invalidResponse
        }
    }

    static func jsonObjectData(in text: String) -> Data? {
        let characters = Array(text.unicodeScalars)
        guard let start = characters.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    var scalars = String.UnicodeScalarView()
                    scalars.append(contentsOf: characters[start...index])
                    return String(scalars).data(using: .utf8)
                }
            default: break
            }
        }
        return nil
    }
}
