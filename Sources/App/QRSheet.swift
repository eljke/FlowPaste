import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    let payload: String
    private var tooLarge: Bool { payload.utf8.count > 1800 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading { ProgressView("Создаём QR-код…") }
                    else if let image {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .frame(maxWidth: 320).accessibilityLabel("QR-код для выбранного текста")
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("QR-код FlowPaste", image: Image(uiImage: image))) {
                            Label("Поделиться QR-кодом", systemImage: "square.and.arrow.up").frame(minHeight: 32)
                        }.buttonStyle(.borderedProminent)
                    } else {
                        ContentUnavailableView(tooLarge ? "Слишком много текста" : "Не удалось создать QR-код",
                            systemImage: "qrcode",
                            description: Text(tooLarge ? "Для надёжного сканирования используйте текст до 1800 байт. Большой текст можно скопировать или отправить." : "Попробуйте более короткий непустой текст."))
                    }
                    Text("QR-код создаётся на устройстве. Любой, кто его отсканирует, увидит этот текст.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity)
            }
            .navigationTitle("QR-код")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task(id: payload) {
                isLoading = true
                image = await Task.detached(priority: .userInitiated) { Self.makeImage(payload) }.value
                isLoading = false
            }
        }
    }

    nonisolated private static func makeImage(_ text: String) -> UIImage? {
        guard !text.isEmpty, text.utf8.count <= 1800 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let background = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: output.extent.insetBy(dx: -4, dy: -4))
        let scaled = output.composited(over: background).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
