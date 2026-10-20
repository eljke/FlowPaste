import Foundation

public enum FlowBackup {
    public static let maximumBytes = 20 * 1_048_576
    public static let maximumClips = 10_000

    public enum BackupError: LocalizedError {
        case tooLarge, invalidFormat, invalidClip, duplicateID
        public var errorDescription: String? {
            switch self {
            case .tooLarge: return "Резервная копия превышает лимит: 20 МБ или 10 000 записей"
            case .invalidFormat: return "Выберите JSON-копию истории FlowPaste"
            case .invalidClip: return "Копия содержит пустую, слишком большую или повреждённую запись"
            case .duplicateID: return "В копии повторяются идентификаторы записей"
            }
        }
    }

    public static func decode(_ data: Data) throws -> [Clip] {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        let clips: [Clip]
        do { clips = try JSONDecoder().decode([Clip].self, from: data) }
        catch { throw BackupError.invalidFormat }
        try validate(clips)
        return clips
    }

    public static func encode(_ clips: [Clip]) throws -> Data {
        try validate(clips)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(clips)
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    static func validate(_ clips: [Clip]) throws {
        guard clips.count <= maximumClips else { throw BackupError.tooLarge }
        var ids = Set<UUID>()
        for clip in clips {
            try validate(clip)
            guard ids.insert(clip.id).inserted else { throw BackupError.duplicateID }
        }
    }

    static func validate(_ clip: Clip) throws {
        guard clip.text.utf8.count <= FlowEngine.maximumTextBytes,
              !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              clip.createdAt.timeIntervalSince1970.isFinite else { throw BackupError.invalidClip }
    }
}
