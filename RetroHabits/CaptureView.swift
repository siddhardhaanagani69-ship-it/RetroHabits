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
                    ProgressView().tint(Comic.ink)
                    Text("Reading the flyer…").font(.comic(14)).foregroundStyle(Comic.ink)
                }
            }
            if let error { Text(error).font(.comic(13)).foregroundStyle(Comic.red) }
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
        ComicPanel(tilt: 0.3) {
            VStack(alignment: .leading, spacing: 10) {
                Text("CAMPUS CAPTURE").font(.bangers(22)).foregroundStyle(Comic.blue)
                Text("Snap an event flyer. I'll check it against your calendar and what you've told me you're into.")
                    .font(.comicLight(12)).foregroundStyle(Comic.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingCamera = true } label: {
                            Label("SNAP", systemImage: "camera.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("PICK PHOTO", systemImage: "photo.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ComicButtonStyle())
                }
                .disabled(isLoading)
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2))
                }
            }
        }
    }

    private func resultPanel(_ r: AssistantService.CaptureResult) -> some View {
        ComicPanel(fill: Comic.yellow.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(r.event.title.uppercased()).font(.bangers(22)).foregroundStyle(Comic.ink)
                if let start = r.event.start {
                    Label(RippleView.range(start, r.event.end), systemImage: "clock.fill")
                        .font(.comic(13)).foregroundStyle(Comic.ink)
                }
                if let location = r.event.location {
                    Label(location, systemImage: "mappin.and.ellipse").font(.comic(13)).foregroundStyle(Comic.ink)
                }
                Label(r.event.cost ?? "Price not on the flyer", systemImage: "tag.fill")
                    .font(.comic(13)).foregroundStyle(r.event.cost == nil ? Comic.red : Comic.ink)

                Divider().overlay(Comic.ink.opacity(0.3))
                ForEach(r.verdict, id: \.self) { line in
                    Text("• \(line)").font(.comic(14)).foregroundStyle(Comic.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !r.interests.isEmpty {
                    WhyButton { inspecting = true }
                }
                ForEach(r.event.assumptions, id: \.self) { assumption in
                    Text("ASSUMED: \(assumption)").font(.comicLight(11)).foregroundStyle(Comic.orange)
                }

                if r.event.isEvent {
                    VStack(spacing: 8) {
                        if r.event.start != nil {
                            Button { saving = true } label: {
                                Label("SAVE TO CALENDAR", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ComicButtonStyle(fill: Comic.blue, textColor: .white))
                            Button { onPlanAround(planSentence(r.event)) } label: {
                                Label("PLAN AROUND IT", systemImage: "dot.radiowaves.right").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                        }
                        Button { withAnimation { result = nil; image = nil; photo = nil } } label: {
                            Text("NOT INTERESTED").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ComicButtonStyle(fill: .white))
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { result = r }
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
