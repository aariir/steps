import Foundation

/// Validates AI-polished captions so the model can't drop or invent UI names.
public enum CaptionGuard {
    static func quoted(_ s: String) -> [String] {
        var out: [String] = []
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "“"), let close = rest[open...].firstIndex(of: "”") {
            out.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return out
    }

    /// Cleans model output (strips numbering, wrapping quotes, extra lines) and returns it only if
    /// it keeps every quoted UI name from the original; otherwise nil.
    public static func accept(original: String, polished: String) -> String? {
        var text = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nl = text.firstIndex(where: \.isNewline) { text = String(text[..<nl]) }
        if let range = text.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) { text.removeSubrange(range) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespaces))
        guard !text.isEmpty, text.count <= original.count * 3 + 40 else { return nil }
        for name in quoted(original) where !text.contains(name) { return nil }
        return text
    }
}
