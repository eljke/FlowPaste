import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

@main
struct FlowPasteApp: App {
    @StateObject private var model = FlowViewModel()
    var body: some Scene { WindowGroup { FlowRootView().environmentObject(model) } }
}

@MainActor
final class FlowViewModel: ObservableObject {
    @Published var input = ""
    @Published var output = ""
    @Published var items: [Clip] = []
    @Published var query = ""
    @Published var feedback: String?
    @Published var showingQR = false
    @Published var currentAction: FlowAction?
    private let store: FlowRepository?
    init() {
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlowPaste", isDirectory: true)
            store = try FlowRepository(url: root.appendingPathComponent("clips.sqlite"))
        } catch {
            store = nil
            feedback = "Не удалось открыть хранилище: \(error.localizedDescription)"
        }
    }
    func paste() {
        if let pasted = UIPasteboard.general.string, !pasted.isEmpty { input = pasted; output = ""; feedback = nil }
        else { feedback = "Буфер пуст или доступ к содержимому запрещён" }
    }
    func transform(_ action: FlowAction) {
        do { output = try FlowEngine.apply(action, to: input); currentAction = action; feedback = nil }
        catch { feedback = error.localizedDescription }
    }
    func copy(_ value: String) { UIPasteboard.general.string = value; feedback = "Скопировано" }
    func save() async {
        guard let store else { return }
        let text = output.isEmpty ? input : output
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { feedback = "Нечего сохранять"; return }
        do { try await store.save(Clip(text: text)); await refresh(); feedback = "Добавлено в историю" }
        catch { feedback = "Ошибка сохранения: \(error.localizedDescription)" }
    }
    func refresh() async {
        guard let store else { return }
        do { items = try await store.list(search: query) }
        catch { feedback = "Ошибка чтения: \(error.localizedDescription)" }
    }
    func togglePin(_ clip: Clip) async {
        guard let store else { return }
        var changed = clip; changed.pinned.toggle()
        do { try await store.save(changed); await refresh() }
        catch { feedback = error.localizedDescription }
    }
    func delete(_ clip: Clip) async {
        guard let store else { return }
        do { try await store.delete(id: clip.id); await refresh() }
        catch { feedback = error.localizedDescription }
    }
    func export() async -> URL? {
        guard let store else { return nil }
        do {
            let bytes = try await store.exportJSON()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FlowPaste-History.json")
            try bytes.write(to: url, options: .atomic)
            return url
        } catch { feedback = error.localizedDescription; return nil }
    }
}

struct FlowRootView: View {
    @EnvironmentObject private var vm: FlowViewModel
    var body: some View {
        TabView {
            FlowWorkbench().tabItem { Label("Инструменты", systemImage: "wand.and.stars") }
            FlowHistory().tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
            FlowSettings().tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .tint(.indigo)
    }
}

struct FlowWorkbench: View {
    @EnvironmentObject private var vm: FlowViewModel
    @FocusState private var editing: Bool
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Входящий текст").font(.headline); Spacer(); Text(FlowEngine.kind(vm.input)).font(.caption).foregroundStyle(.secondary) }
                        TextEditor(text: $vm.input).focused($editing).frame(minHeight: 125).scrollContentBackground(.hidden).padding(8)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Текст для обработки")
                        HStack {
                            Button { editing = false; vm.paste() } label: { Label("Вставить", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                            Button { editing = false; vm.input = ""; vm.output = "" } label: { Label("Очистить", systemImage: "xmark.circle") }.buttonStyle(.bordered)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Быстрые действия").font(.headline)
                        LazyVGrid(columns: columns, spacing: 9) {
                            ForEach(FlowAction.allCases) { action in
                                Button { editing = false; vm.transform(action) } label: {
                                    HStack { Text(action.title).font(.subheadline); Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.caption) }
                                        .padding(12).frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if !vm.output.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Результат").font(.headline)
                            Text(vm.output).font(.body.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                            HStack {
                                Button { vm.copy(vm.output) } label: { Label("Копировать", systemImage: "doc.on.doc") }.buttonStyle(.borderedProminent)
                                Button { vm.input = vm.output; vm.output = "" } label: { Label("Дальше", systemImage: "arrow.up") }.buttonStyle(.bordered)
                            }
                        }
                    }
                    HStack {
                        Button { Task { await vm.save() } } label: { Label("Сохранить в историю", systemImage: "bookmark") }.buttonStyle(.borderedProminent)
                        Button { vm.showingQR = true } label: { Label("QR", systemImage: "qrcode") }.buttonStyle(.bordered)
                    }
                    if let feedback = vm.feedback { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
                }.padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("FlowPaste")
            .sheet(isPresented: $vm.showingQR) { QRSheet(payload: vm.output.isEmpty ? vm.input : vm.output) }
        }
    }
}

struct QRSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payload: String
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = Self.makeImage(payload) { Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 260, height: 260) }
                else { ContentUnavailableView("Нет QR-кода", systemImage: "qrcode", description: Text("Вставь непустой текст")) }
                Text("QR создаётся полностью на устройстве").font(.footnote).foregroundStyle(.secondary)
            }.padding().navigationTitle("QR-код").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
    static func makeImage(_ text: String) -> UIImage? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = data; filter.correctionLevel = "M"
        let context = CIContext()
        guard let output = filter.outputImage, let cg = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: output.extent.applying(CGAffineTransform(scaleX: 10, y: 10))) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct FlowHistory: View {
    @EnvironmentObject private var vm: FlowViewModel
    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty { ContentUnavailableView("Пока пусто", systemImage: "tray", description: Text("Сохрани нужный текст из раздела «Инструменты»")) }
                else {
                    List {
                        ForEach(vm.items) { item in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(item.text).lineLimit(4).textSelection(.enabled)
                                HStack {
                                    Text(item.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { vm.copy(item.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                                    Button { Task { await vm.togglePin(item) } } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }.buttonStyle(.borderless)
                                }
                            }.padding(.vertical, 4)
                            .swipeActions { Button(role: .destructive) { Task { await vm.delete(item) } } label: { Label("Удалить", systemImage: "trash") } }
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("История")
            .searchable(text: $vm.query, prompt: "Найти сохранённое")
            .task(id: vm.query) { await vm.refresh() }
            .refreshable { await vm.refresh() }
        }
    }
}

struct FlowSettings: View {
    @EnvironmentObject private var vm: FlowViewModel
    @State private var backup: URL?
    var body: some View {
        NavigationStack {
            Form {
                Section("Приватность") {
                    Label("Нет аккаунтов и аналитики", systemImage: "hand.raised")
                    Label("Буфер читается только по нажатию", systemImage: "hand.tap")
                    Label("История остаётся на iPhone", systemImage: "iphone")
                }
                Section("Данные") {
                    Button("Подготовить JSON-бэкап") { Task { backup = await vm.export() } }
                    if let backup { ShareLink(item: backup) { Label("Поделиться резервной копией", systemImage: "square.and.arrow.up") } }
                }
                Section { Text("Для LiveContainer: гостевые приложения не изолированы друг от друга. Не сохраняй в историю пароли и токены.").font(.footnote) }
            }.navigationTitle("Настройки")
        }
    }
}
