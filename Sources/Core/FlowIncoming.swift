import Foundation

public enum FlowIncoming: Equatable, Sendable {
    case text(String)
    case file(URL)

    public enum IncomingError: LocalizedError {
        case invalidURL, invalidTextFile
        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Не удалось прочитать переданную ссылку"
            case .invalidTextFile: return "Передайте текстовый файл в кодировке UTF-8"
            }
        }
    }

    public init(url: URL) throws {
        if url.scheme?.lowercased() == "flowpaste" {
            guard url.absoluteString.utf8.count <= 3 * FlowEngine.maximumTextBytes + 1024 else { throw FlowError.textTooLarge }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.host == "import", components.path.isEmpty, components.fragment == nil,
                  let items = components.queryItems, items.count == 1,
                  items[0].name == "text", let text = items[0].value else { throw IncomingError.invalidURL }
            try FlowEngine.validate(text)
            self = .text(text)
            return
        }
        try FlowEngine.validate(url.absoluteString)
        guard url.scheme != nil else { throw IncomingError.invalidURL }
        self = url.isFileURL ? .file(url) : .text(url.absoluteString)
    }

    public static func decodeFile(_ data: Data) throws -> String {
        guard data.count <= FlowEngine.maximumTextBytes else { throw FlowError.textTooLarge }
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        guard let text = String(data: bytes, encoding: .utf8) else { throw IncomingError.invalidTextFile }
        try FlowEngine.validate(text)
        return text
    }
}
