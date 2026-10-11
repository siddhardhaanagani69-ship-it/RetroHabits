import SwiftUI
import PhotosUI

/// Log a purchase by typing, speaking or snapping the receipt. The amount always
/// comes from what you said or the receipt — if there isn't one, it asks.
struct AddSpendingCard: View {
    @ObservedObject private var money = MoneyStore.shared
    @StateObject private var dictation = Dictation()
    @State private var draft = ""
    @State private var photo: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Log spending").font(.headline)
                TextField(dictation.isListening ? "Listening…" : "\"$12 on lunch at Chipotle\"", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(Palette.paper)
                    .clipShape(.rect(cornerRadius: 8))
                    .onSubmit { Task { await add() } }
                HStack(spacing: 8) {
                    Button { Task { await toggleMic() } } label: {
                        Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(FilledButtonStyle(fill: dictation.isListening ? Palette.red : Palette.fill,
                                                   textColor: dictation.isListening ? .white : Palette.accent))
                    .accessibilityLabel(dictation.isListening ? "Stop and add" : "Say what you spent")

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingCamera = true } label: { Image(systemName: "camera.fill") }
                            .buttonStyle(FilledButtonStyle())
                            .accessibilityLabel("Scan a receipt")
                    }
                    PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "doc.text.image") }
                        .buttonStyle(FilledButtonStyle())
                        .accessibilityLabel("Pick a receipt photo")

                    Button { Task { await add() } } label: {
                        Group { if isSaving { ProgressView().tint(.white) } else { Text("Add") } }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(fill: Palette.accent, textColor: .white))
                    .disabled(isSaving || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .disabled(isSaving)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(messageIsError ? Palette.red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = dictation.error {
                    Text(error).font(.footnote).foregroundStyle(Palette.red)
                }
            }
        }
        .onChange(of: dictation.transcript) { _, heard in
            if dictation.isListening { draft = heard }
        }
        .onChange(of: photo) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await addReceipt(image)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in Task { await addReceipt(image) } }
                .ignoresSafeArea()
        }
    }

    private func toggleMic() async {
        if dictation.isListening {
            draft = dictation.stop()
            await add()
        } else {
            message = nil
            await dictation.start()
        }
    }

    private func add() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await save { try await money.add(text: text) }
        if !messageIsError { draft = "" }
    }

    private func addReceipt(_ image: UIImage) async {
        guard let jpeg = image.receiptJPEG() else { return }
        await save { try await money.add(receiptJPEG: jpeg) }
        photo = nil
    }

    private func save(_ work: () async throws -> AssistantService.Spend) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let entry = try await work()
            messageIsError = false
            let what = [entry.note, entry.merchant.map { "at \($0)" }].compactMap { $0 }.joined(separator: " ")
            message = "Added \(BudgetCard.money(entry.amount)) · \(entry.category)" + (what.isEmpty ? "" : " — \(what)")
        } catch {
            messageIsError = true
            message = error.localizedDescription
        }
    }
}

private extension UIImage {
    /// Receipts are read as text: 1600 px on the long side is plenty.
    func receiptJPEG() -> Data? {
        let scale = min(1, 1600 / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: 0.7)
    }
}
