import Foundation

public struct Clip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var pinned: Bool
    public init(id: UUID = UUID(), text: String, createdAt: Date = .now, pinned: Bool = false) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.pinned = pinned
    }
}

public enum FlowAction: String, CaseIterable, Identifiable, Sendable {
    case cleanLink, prettyJSON, compactJSON, deduplicateLines, sortLines, trimSpaces, upperCase, lowerCase, encodeBase64, decodeBase64
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cleanLink: return "Очистить ссылку"
        case .prettyJSON: return "Форматировать JSON"
        case .compactJSON: return "Сжать JSON"
        case .deduplicateLines: return "Убрать повторы"
        case .sortLines: return "Сортировать строки"
        case .trimSpaces: return "Убрать лишние пробелы"
        case .upperCase: return "В ВЕРХНИЙ РЕГИСТР"
        case .lowerCase: return "в нижний регистр"
        case .encodeBase64: return "Кодировать Base64"
        case .decodeBase64: return "Декодировать Base64"
        }
    }
}

public enum FlowError: LocalizedError {
    case invalidJSON, invalidBase64, invalidURL, emptyText
    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Это не корректный JSON"
        case .invalidBase64: return "Это не корректный UTF-8 Base64"
        case .invalidURL: return "Введите полноценную http/https ссылку"
        case .emptyText: return "Сначала вставь текст"
        }
    }
}

/// Pure deterministic transformations. No clipboard monitoring, network, or side effects.
public enum FlowEngine {
    private static let trackers: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "igshid", "mc_cid", "mc_eid", "yclid", "_hsenc", "_hsmi"]
    public static func kind(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URLComponents(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil { return "Ссылка" }
        if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])) != nil { return "JSON" }
        if trimmed.contains("\n") { return "Многострочный текст" }
        return "Текст"
    }
    public static func apply(_ action: FlowAction, to input: String) throws -> String {
        guard !input.isEmpty else { throw FlowError.emptyText }
        switch action {
        case .cleanLink:
            guard var c = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["http", "https"].contains(c.scheme?.lowercased() ?? ""), c.host != nil else { throw FlowError.invalidURL }
            c.queryItems = c.queryItems?.filter { item in
                let k = item.name.lowercased()
                return !k.hasPrefix("utm_") && !trackers.contains(k)
            }
            return c.url?.absoluteString ?? input
        case .prettyJSON, .compactJSON:
            guard let obj = try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed]),
                  let d = try? JSONSerialization.data(withJSONObject: obj, options: action == .prettyJSON ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes] : [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]),
                  let output = String(data: d, encoding: .utf8) else { throw FlowError.invalidJSON }
            return output
        case .deduplicateLines:
            var used = Set<String>()
            return input.components(separatedBy: .newlines).filter { used.insert($0).inserted }.joined(separator: "\n")
        case .sortLines:
            return input.components(separatedBy: .newlines).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .trimSpaces:
            return input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .upperCase: return input.uppercased()
        case .lowerCase: return input.lowercased()
        case .encodeBase64: return Data(input.utf8).base64EncodedString()
        case .decodeBase64:
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)), let decoded = String(data: data, encoding: .utf8) else { throw FlowError.invalidBase64 }
            return decoded
        }
    }
}
