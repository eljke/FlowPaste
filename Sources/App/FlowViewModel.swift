import SwiftUI
import UIKit

@MainActor
final class FlowViewModel: ObservableObject {
    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
            transformTask?.cancel()
            output = nil
            currentAction = nil
            isProcessing = false
            feedback = nil
            detectContent()
        }
    }
    @Published private(set) var output: String?
    @Published private(set) var kind = "Нет текста"
    @Published private(set) var suggestions: [FlowAction] = []
    @Published private(set) var items: [Clip] = []
    @Published private(set) var totalCount = 0
    @Published var query = ""
    @Published var feedback: String?
    @Published private(set) var historyError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isProcessing = false
    @Published private(set) var isSaving = false
    @Published private(set) var isTransferring = false
    @Published private(set) var currentAction: FlowAction?
    @Published private(set) var deletedClip: Clip?
    @Published var selectedTab = 0
    @Published private(set) var pendingIncomingText: String?
    @Published private(set) var isReceiving = false
    private let store: FlowRepository?
    private var transformTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var refreshID = UUID()
    private var incomingID = UUID()
    var textToUse: String { output ?? input }
    var canUseText: Bool { !textToUse.isEmpty && textToUse.utf8.count <= FlowEngine.maximumTextBytes && !isProcessing }
    var storageAvailable: Bool { store != nil }

    init() {
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlowPaste", isDirectory: true)
            store = try FlowRepository(url: root.appendingPathComponent("clips.sqlite"))
        } catch {
            store = nil
            historyError = error.localizedDescription
        }
    }

    private func detectContent() {
        detectionTask?.cancel()
        let text = input
        detectionTask = Task {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) { (FlowEngine.kind(text), FlowEngine.suggestions(for: text)) }.value
            guard !Task.isCancelled, input == text else { return }
            kind = result.0
            suggestions = result.1
        }
    }

    func paste() {
        if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
            input = pasted
            feedback = pasted.utf8.count > FlowEngine.maximumTextBytes ? FlowError.textTooLarge.localizedDescription : nil
        } else { feedback = "Буфер пуст или доступ к содержимому запрещён" }
    }

    func receive(_ url: URL) async {
        let id = UUID()
        incomingID = id
        isReceiving = true
        defer { if incomingID == id { isReceiving = false } }
        do {
            let text: String
            switch try FlowIncoming(url: url) {
            case .text(let value): text = value
            case .file(let fileURL):
                text = try await Task.detached(priority: .userInitiated) {
                    let scoped = fileURL.startAccessingSecurityScopedResource()
                    defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
                    let file = try FileHandle(forReadingFrom: fileURL)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: FlowEngine.maximumTextBytes + 1) ?? Data()
                    return try FlowIncoming.decodeFile(data)
                }.value
            }
            guard incomingID == id else { return }
            selectedTab = 0
            guard input != text, pendingIncomingText != text else { return }
            if input.isEmpty && output == nil { openIncoming(text) }
            else { pendingIncomingText = text }
        } catch {
            guard incomingID == id else { return }
            selectedTab = 0
            feedback = "Не удалось принять содержимое: \(error.localizedDescription)"
        }
    }

    func acceptIncoming(_ text: String) {
        pendingIncomingText = nil
        openIncoming(text)
    }

    func cancelIncoming() { pendingIncomingText = nil }

    private func openIncoming(_ text: String) {
        input = text
        output = nil
        currentAction = nil
        selectedTab = 0
        feedback = "Получено через «Поделиться»"
    }

    func transform(_ action: FlowAction) {
        transformTask?.cancel()
        let text = input
        output = nil
        currentAction = nil
        feedback = nil
        isProcessing = true
        transformTask = Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try FlowEngine.apply(action, to: text) } }.value
            guard !Task.isCancelled, input == text else { return }
            isProcessing = false
            switch result {
            case .success(let value): output = value; currentAction = action
            case .failure(let error): feedback = error.localizedDescription
            }
        }
    }

    func useResult() {
        guard let output else { return }
        input = output
        self.output = nil
        currentAction = nil
    }

    func clear() { input = ""; output = nil; feedback = nil }
    func copy(_ value: String) { UIPasteboard.general.string = value; feedback = "Скопировано" }
    func open(_ clip: Clip) { input = clip.text; output = nil; selectedTab = 0; feedback = "Открыто из истории" }

    func save() async {
        guard let store, !isSaving else { return }
        let text = textToUse
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.save(Clip(text: text))
            await refresh()
            feedback = "Добавлено в историю"
        } catch { feedback = error.localizedDescription }
    }

    func refresh() async {
        guard let store else { return }
        let id = UUID()
        refreshID = id
        let search = query
        isLoading = true
        defer { if refreshID == id { isLoading = false } }
        do {
            let found = try await store.list(search: search)
            let count = try await store.count()
            guard refreshID == id, query == search, !Task.isCancelled else { return }
            items = found
            totalCount = count
            historyError = nil
        } catch {
            guard refreshID == id, !Task.isCancelled else { return }
            historyError = error.localizedDescription
        }
    }

    func togglePin(_ clip: Clip) async {
        guard let store else { return }
        do { try await store.togglePin(id: clip.id); await refresh() }
        catch { historyError = error.localizedDescription }
    }

    func delete(_ clip: Clip) async {
        guard let store else { return }
        do {
            try await store.delete(id: clip.id)
            deletedClip = clip
            await refresh()
        } catch { historyError = error.localizedDescription }
    }

    func undoDelete() async {
        guard let store, let clip = deletedClip else { return }
        do {
            try await store.save(clip)
            deletedClip = nil
            await refresh()
        } catch { historyError = error.localizedDescription }
    }

    func export() async -> URL? {
        guard let store, !isTransferring else { return nil }
        isTransferring = true
        defer { isTransferring = false }
        do {
            let bytes = try await store.exportJSON()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlowPaste-Exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("FlowPaste-\(UUID().uuidString).json")
            try bytes.write(to: url, options: [.atomic, .completeFileProtection])
            feedback = "Резервная копия готова"
            return url
        } catch { feedback = error.localizedDescription; return nil }
    }

    func previewImport(_ url: URL) async -> [Clip]? {
        guard !isTransferring else { return nil }
        isTransferring = true
        defer { isTransferring = false }
        do {
            return try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: FlowBackup.maximumBytes + 1) ?? Data()
                return try FlowBackup.decode(data)
            }.value
        } catch { feedback = error.localizedDescription; return nil }
    }

    func restore(_ clips: [Clip]) async {
        guard let store, !isTransferring else { return }
        isTransferring = true
        defer { isTransferring = false }
        do {
            let inserted = try await store.restore(clips)
            await refresh()
            feedback = "Добавлено записей: \(inserted). Уже в истории: \(clips.count - inserted)"
        } catch { feedback = error.localizedDescription }
    }
}
