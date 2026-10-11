import SwiftUI
import PhotosUI

/// Campus Capture: photograph a flyer, get a personal fit check — calendar,
/// interests you've actually shared, and what the flyer leaves out.
struct CaptureView: View {
    @EnvironmentObject var agenda: AgendaStore
    @EnvironmentObject var habits: HabitStore
    /// "Plan around it" hands Ripple Mode a sentence describing the event.
    let onPlanAround: (String) -> Void

    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: AssistantService.CaptureResult?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingCamera = false
    @State private var saving = false
    @State private var inspecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pickerPanel
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(Palette.ink)
                    Text("Reading the flyer…").font(.bodyMedium(14)).foregroundStyle(Palette.ink)
                }
            }
            if let error { Text(error).font(.bodyMedium(13)).foregroundStyle(Palette.red) }
            if let result { resultPanel(result) }
        }
        .onChange(of: photo) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let picked = UIImage(data: data) else { return }
                await analyze(picked)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { picked in Task { await analyze(picked) } }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $saving) {
            if let ev = result?.event, let start = ev.start {
                EventEditor(title: ev.title, start: start, end: ev.end ?? start.addingTimeInterval(3600))
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $inspecting) {
            if let result {
                MemoryInspector(title: "Why this matched your interests.",
                                memories: result.interests.map(\.memory)) {
                    if let image { await analyze(image) }   // re-check with the corrected memory
                }
            }
        }
    }

    private var pickerPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Campus Capture").font(.heading(22)).foregroundStyle(Palette.accent)
                Text("Snap an event flyer. I'll check it against your calendar and what you've told me you're into.")
                    .font(.bodyRegular(12)).foregroundStyle(Palette.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingCamera = true } label: {
                            Label("Snap", systemImage: "camera.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Pick Photo", systemImage: "photo.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle())
                }
                .disabled(isLoading)
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))
                }
            }
        }
    }

    private func resultPanel(_ r: AssistantService.CaptureResult) -> some View {
        Card(fill: Palette.yellow.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(r.event.title).font(.heading(22)).foregroundStyle(Palette.ink)
                if let start = r.event.start {
                    Label(RippleView.range(start, r.event.end), systemImage: "clock.fill")
                        .font(.bodyMedium(13)).foregroundStyle(Palette.ink)
                }
                if let location = r.event.location {
                    Label(location, systemImage: "mappin.and.ellipse").font(.bodyMedium(13)).foregroundStyle(Palette.ink)
                }
                Label(r.event.cost ?? "Price not on the flyer", systemImage: "tag.fill")
                    .font(.bodyMedium(13)).foregroundStyle(r.event.cost == nil ? Palette.red : Palette.ink)

                Divider().overlay(Palette.ink.opacity(0.3))
                ForEach(r.verdict, id: \.self) { line in
                    Text("• \(line)").font(.bodyMedium(14)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !r.interests.isEmpty {
                    WhyButton { inspecting = true }
                }
                ForEach(r.event.assumptions, id: \.self) { assumption in
                    Text("Assumed: \(assumption)").font(.bodyRegular(11)).foregroundStyle(Palette.orange)
                }

                if r.event.isEvent {
                    VStack(spacing: 8) {
                        if r.event.start != nil {
                            Button { saving = true } label: {
                                Label("Save to Calendar", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FilledButtonStyle(fill: Palette.accent, textColor: .white))
                            Button { onPlanAround(planSentence(r.event)) } label: {
                                Label("Plan Around It", systemImage: "dot.radiowaves.right").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                        }
                        Button { withAnimation { result = nil; image = nil; photo = nil } } label: {
                            Text("Not Interested").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle())
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func planSentence(_ ev: AssistantService.CaptureResult.Event) -> String {
        guard let start = ev.start else { return "What if I go to \(ev.title)?" }
        return "What if I go to \(ev.title) on \(RippleView.range(start, ev.end))?"
    }

    private func analyze(_ picked: UIImage) async {
        image = picked
        isLoading = true
        error = nil
        defer { isLoading = false }
        guard let jpeg = picked.downscaled(maxSide: 1600).jpegData(compressionQuality: 0.7) else { return }
        do {
            let r = try await AssistantService.capture(imageJPEG: jpeg, agenda: agenda.items, habits: habits.habits)
            withAnimation(.easeOut(duration: 0.2)) { result = r }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension UIImage {
    /// Phone photos are ~12 MP; 1600 px on the long side is plenty to read a flyer.
    func downscaled(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// The system camera, for snapping a flyer a judge hands you.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
