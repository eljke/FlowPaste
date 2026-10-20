import SwiftUI

struct FlowHistory: View {
    @EnvironmentObject private var vm: FlowViewModel
    @State private var selectedClip: Clip?

    var body: some View {
        NavigationStack {
            Group {
                if let error = vm.historyError {
                    ContentUnavailableView {
                        Label("История недоступна", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("Повторить") { Task { await vm.refresh() } }.buttonStyle(.bordered)
                    }
                } else if vm.isLoading && vm.items.isEmpty {
                    ProgressView("Загружаем историю…")
                } else if vm.items.isEmpty {
                    ContentUnavailableView(vm.query.isEmpty ? "Всё нужное — под рукой" : "Ничего не найдено",
                        systemImage: vm.query.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(vm.query.isEmpty ? "Сохраните текст из инструментов. Здесь можно найти, закрепить и открыть его снова." : "Попробуйте другое слово или часть текста."))
                } else {
                    List {
                        Section {
                            ForEach(vm.items) { item in row(item) }
                        } footer: {
                            Text(vm.items.count == 500 ? "Показаны первые 500 совпадений. Уточните поиск. Всего в истории: \(vm.totalCount)." : "Показано: \(vm.items.count). Всего в истории: \(vm.totalCount).")
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("История")
            .searchable(text: $vm.query, prompt: "Найти сохранённое")
            .task(id: vm.query) { await vm.refresh() }
            .refreshable { await vm.refresh() }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if vm.deletedClip != nil {
                        HStack {
                            Text("Запись удалена").font(.subheadline)
                            Spacer()
                            Button("Отменить") { Task { await vm.undoDelete() } }.frame(minHeight: 44)
                        }.padding(.horizontal)
                    }
                    if vm.feedback != nil { FlowFeedback(message: vm.feedback).padding() }
                }.background(.regularMaterial)
            }
            .sheet(item: $selectedClip) { clip in ClipDetail(clip: clip) }
        }
    }

    private func row(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { selectedClip = clip } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if clip.pinned { Label("Закреплено", systemImage: "pin.fill").font(.caption).foregroundStyle(.indigo) }
                    Text(String(clip.text.prefix(240))).font(.body).foregroundStyle(.primary).lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle()).frame(minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityHint("Открыть запись целиком")
            HStack {
                Text(clip.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { vm.copy(clip.text) } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Копировать запись")
                Button { Task { await vm.togglePin(clip) } } label: {
                    Image(systemName: clip.pinned ? "pin.fill" : "pin").frame(width: 44, height: 44)
                }.buttonStyle(.borderless).accessibilityLabel(clip.pinned ? "Открепить запись" : "Закрепить запись")
            }
        }
        .swipeActions(allowsFullSwipe: false) {
            Button(role: .destructive) { Task { await vm.delete(clip) } } label: { Label("Удалить", systemImage: "trash") }
        }
        .contextMenu {
            Button { selectedClip = clip } label: { Label("Открыть", systemImage: "doc.text") }
            Button { vm.copy(clip.text) } label: { Label("Копировать", systemImage: "doc.on.doc") }
            ShareLink(item: clip.text)
        }
        .padding(.top, 6)
    }
}

private struct ClipDetail: View {
    @EnvironmentObject private var vm: FlowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingOpen = false
    @State private var showingQR = false
    let clip: Clip

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(clip.createdAt, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    Text(String(clip.text.prefix(12_000))).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if clip.text.count > 12_000 { Text("Предпросмотр: первые 12 000 символов. Действия используют всю запись.").font(.caption).foregroundStyle(.secondary) }
                    Button { vm.copy(clip.text) } label: { Label("Копировать", systemImage: "doc.on.doc").frame(minHeight: 32) }.buttonStyle(.borderedProminent)
                    Button {
                        if !vm.input.isEmpty && vm.input != clip.text { confirmingOpen = true }
                        else { open() }
                    } label: { Label("Открыть в инструментах", systemImage: "wand.and.stars").frame(minHeight: 32) }.buttonStyle(.bordered)
                    ShareLink(item: clip.text) { Label("Поделиться", systemImage: "square.and.arrow.up").frame(minHeight: 44) }
                    Button { showingQR = true } label: { Label("QR-код", systemImage: "qrcode").frame(minHeight: 44) }
                    FlowFeedback(message: vm.feedback)
                }.padding()
            }
            .navigationTitle("Запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .confirmationDialog("Заменить исходный текст в инструментах?", isPresented: $confirmingOpen, titleVisibility: .visible) {
                Button("Открыть запись") { open() }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(isPresented: $showingQR) { QRSheet(payload: clip.text) }
        }
    }

    private func open() { vm.open(clip); dismiss() }
}
