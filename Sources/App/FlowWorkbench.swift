import SwiftUI

struct FlowWorkbench: View {
    @EnvironmentObject private var vm: FlowViewModel
    @FocusState private var editing: Bool
    @State private var showingQR = false
    @State private var showingClear = false
    @State private var showingAllActions = false
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    introduction
                    if vm.isReceiving { ProgressView("Принимаем содержимое…") }
                    editor
                    if !vm.suggestions.isEmpty {
                        actions(vm.suggestions, title: "Подходит для этого текста")
                    }
                    DisclosureGroup("Все инструменты", isExpanded: $showingAllActions) {
                        actions(FlowAction.allCases, title: nil).padding(.top, 12)
                    }.font(.headline)
                    if vm.isProcessing { ProgressView("Обрабатываем на устройстве…").frame(maxWidth: .infinity) }
                    if let result = vm.output { resultCard(result) }
                    ViewThatFits(in: .horizontal) {
                        HStack { saveButton; qrButton }
                        VStack(alignment: .leading) { saveButton; qrButton }
                    }
                    FlowFeedback(message: vm.feedback)
                    if !vm.storageAvailable { FlowFeedback(message: vm.historyError) }
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("FlowPaste")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { editing = false } }
            }
            .sheet(isPresented: $showingQR) { QRSheet(payload: vm.textToUse) }
            .confirmationDialog("Очистить текст и результат?", isPresented: $showingClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { vm.clear() }
                Button("Отмена", role: .cancel) {}
            } message: { Text("Сохранённые записи останутся в истории.") }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Из буфера — в дело", systemImage: "sparkles").font(.title2.bold())
            Text("В другом приложении нажмите «Поделиться» → LiveContainer → FlowPaste. Ссылка или текстовый файл откроется здесь.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Исходный текст").font(.headline)
                Spacer()
                Text(vm.kind).font(.caption.weight(.medium)).foregroundStyle(.indigo)
            }
            ZStack(alignment: .topLeading) {
                if vm.input.isEmpty {
                    Text("Ссылка, JSON или обычный текст…").foregroundStyle(.tertiary).padding(13).accessibilityHidden(true)
                }
                TextEditor(text: $vm.input).focused($editing).frame(minHeight: 150, maxHeight: 240)
                    .scrollContentBackground(.hidden).padding(8)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Текст для обработки")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            HStack {
                Button { editing = false; vm.paste() } label: {
                    Label("Вставить", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.borderedProminent).keyboardShortcut("v", modifiers: .command)
                Button { editing = false; showingClear = true } label: {
                    Image(systemName: "xmark").frame(minWidth: 32, minHeight: 32)
                }.buttonStyle(.bordered).accessibilityLabel("Очистить текст")
                    .disabled(vm.input.isEmpty && vm.output == nil)
            }
            HStack {
                Text("\(vm.input.count) символов")
                Spacer()
                Text("До 1 МБ")
            }.font(.caption).foregroundStyle(.secondary)
            if vm.input.isEmpty {
                Button("Попробовать на примере") {
                    vm.input = "https://example.org/article?id=42&utm_source=newsletter&fbclid=tracking#read"
                }.font(.subheadline).frame(minHeight: 44)
            }
        }
    }

    private func actions(_ actions: [FlowAction], title: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(actions) { action in
                    Button { editing = false; vm.transform(action) } label: {
                        HStack(alignment: .top) {
                            Text(action.title).font(.subheadline.weight(.medium))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.caption).accessibilityHidden(true)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(vm.input.isEmpty || vm.isProcessing)
                }
            }
        }
    }

    private func resultCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Результат", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.indigo)
            if let action = vm.currentAction { Text(action.title).font(.caption).foregroundStyle(.secondary) }
            Text(text.isEmpty ? "Пустой результат" : String(text.prefix(12_000)))
                .font(.body.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            if text.count > 12_000 {
                Text("Показаны первые 12 000 символов. Копирование и отправка используют полный результат.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { resultButtons(text) }
                VStack(alignment: .leading) { resultButtons(text) }
            }
        }
    }

    @ViewBuilder private func resultButtons(_ text: String) -> some View {
        Button { vm.copy(text) } label: { Label("Копировать", systemImage: "doc.on.doc").frame(minHeight: 32) }.buttonStyle(.borderedProminent)
        ShareLink(item: text) { Image(systemName: "square.and.arrow.up").frame(minWidth: 32, minHeight: 32) }
            .buttonStyle(.bordered).accessibilityLabel("Поделиться результатом")
        Button { vm.useResult() } label: { Image(systemName: "arrow.up").frame(minWidth: 32, minHeight: 32) }
            .buttonStyle(.bordered).accessibilityLabel("Использовать результат как исходный текст")
    }

    private var saveButton: some View {
        Button { editing = false; Task { await vm.save() } } label: {
            Label(vm.isSaving ? "Сохраняем…" : "В историю", systemImage: "bookmark").frame(minHeight: 32)
        }.buttonStyle(.borderedProminent).disabled(!vm.canUseText || !vm.storageAvailable || vm.isSaving)
    }

    private var qrButton: some View {
        Button { editing = false; showingQR = true } label: {
            Label("QR-код", systemImage: "qrcode").frame(minHeight: 32)
        }.buttonStyle(.bordered).disabled(!vm.canUseText)
    }
}
