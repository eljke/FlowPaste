import SwiftUI

@main
struct FlowPasteApp: App {
    @StateObject private var model = FlowViewModel()
    var body: some Scene {
        WindowGroup {
            FlowRootView().environmentObject(model)
                .onOpenURL { url in Task { await model.receive(url) } }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { Task { await model.receive(url) } }
                }
        }
    }
}

struct FlowRootView: View {
    @EnvironmentObject private var vm: FlowViewModel
    var body: some View {
        TabView(selection: $vm.selectedTab) {
            FlowWorkbench().tabItem { Label("Инструменты", systemImage: "wand.and.stars") }.tag(0)
            FlowHistory().tabItem { Label("История", systemImage: "clock.arrow.circlepath") }.tag(1)
            FlowSettings().tabItem { Label("Настройки", systemImage: "gearshape") }.tag(2)
        }
        .tint(.indigo)
        .task { await vm.refresh() }
        .alert("Открыть полученный текст?", isPresented: Binding(
            get: { vm.pendingIncomingText != nil },
            set: { if !$0 { vm.cancelIncoming() } }
        ), presenting: vm.pendingIncomingText) { text in
            Button("Заменить текст") { vm.acceptIncoming(text) }
            Button("Отмена", role: .cancel) { vm.cancelIncoming() }
        } message: { _ in
            Text("Исходный текст и результат будут заменены. Сохранённая история останется.")
        }
    }
}

struct FlowFeedback: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityAddTraits(.updatesFrequently)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
