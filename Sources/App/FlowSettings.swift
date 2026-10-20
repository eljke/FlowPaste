import SwiftUI
import UniformTypeIdentifiers

struct FlowSettings: View {
    @EnvironmentObject private var vm: FlowViewModel
    @State private var backup: URL?
    @State private var importing = false
    @State private var showingPreview = false
    @State private var pendingClips: [Clip] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Нет аккаунтов и аналитики", systemImage: "hand.raised")
                    Label("Буфер читается по нажатию", systemImage: "hand.tap")
                    Label("Обработка без интернета", systemImage: "iphone")
                } header: { Text("Приватность") } footer: {
                    Text("Текст сохраняется только кнопкой «В историю». Приложение не следит за буфером других приложений.")
                }
                Section {
                    LabeledContent("Сохранено записей", value: "\(vm.totalCount)")
                    Button { Task { backup = await vm.export() } } label: {
                        Label("Создать резервную копию", systemImage: "square.and.arrow.up")
                    }.disabled(!vm.storageAvailable || vm.isTransferring)
                    if let backup {
                        ShareLink(item: backup) { Label("Сохранить или отправить JSON", systemImage: "square.and.arrow.up.on.square") }
                    }
                    Button { importing = true } label: {
                        Label("Восстановить из JSON", systemImage: "square.and.arrow.down")
                    }.disabled(!vm.storageAvailable || vm.isTransferring)
                    if vm.isTransferring { ProgressView("Подготавливаем данные…") }
                } header: { Text("История и резервные копии") } footer: {
                    Text("Копия содержит полный текст. Храните её в надёжном месте. Восстановление добавляет отсутствующие записи и сохраняет текущие. Лимит копии: 20 МБ, 10 000 записей.")
                }
                if let message = vm.feedback { Section { FlowFeedback(message: message) } }
                if let message = vm.historyError { Section { FlowFeedback(message: message) } }
                Section("LiveContainer") {
                    Text("Гостевые приложения могут иметь доступ к общим данным контейнера. Не сохраняйте пароли и токены в историю.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("О приложении") {
                    LabeledContent("Версия", value: version)
                    Text("FlowPaste превращает вставленный текст в готовый результат: ссылки, JSON, строки, Base64 и QR-коды.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .task { await vm.refresh() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    Task {
                        if let clips = await vm.previewImport(url) { pendingClips = clips; showingPreview = true }
                    }
                case .failure(let error): vm.feedback = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingPreview, onDismiss: { pendingClips = [] }) { importPreview }
        }
    }

    private var importPreview: some View {
        NavigationStack {
            Form {
                Section("Проверка копии") {
                    LabeledContent("Записей в файле", value: "\(pendingClips.count)")
                    LabeledContent("Закреплено", value: "\(pendingClips.filter(\.pinned).count)")
                    Text("Текущая история сохранится. Записи с уже известными идентификаторами будут пропущены.")
                }
                Section {
                    Button("Восстановить историю") {
                        let clips = pendingClips
                        showingPreview = false
                        Task { await vm.restore(clips) }
                    }.disabled(pendingClips.isEmpty)
                }
            }
            .navigationTitle("Восстановление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showingPreview = false } } }
        }
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
