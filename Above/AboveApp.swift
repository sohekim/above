import SwiftUI
import UIKit
import AVFoundation

private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

struct SkyEntry: Codable, Identifiable {
    var id: String
    var date: Date
    var note: String
    var isSample: Bool? = nil
}

@MainActor final class SkyStore: ObservableObject {
    @Published var entries: [SkyEntry] = []
    @Published var error: String?
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Skies")
    init() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("entries.json")
            if FileManager.default.fileExists(atPath: url.path) {
                entries = try JSONDecoder().decode([SkyEntry].self, from: Data(contentsOf: url))
            }
        } catch { self.error = "Your saved skies couldn’t be loaded. \(error.localizedDescription)" }
        seedSamples()
    }
    private func seedSamples() {
        guard !UserDefaults.standard.bool(forKey: "seededSkySamplesV1") else { return }
        let calendar = Calendar.current
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let samples = [(1, "blue"), (3, "gray"), (5, "pink"), (7, "blue"), (9, "gray"), (12, "pink")]
        for (day, name) in samples {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: month),
                  date < calendar.startOfDay(for: Date()), entry(date) == nil,
                  let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "DemoSkies"),
                  let image = UIImage(contentsOfFile: url.path) else { continue }
            save(image, on: date)
            if let index = entries.firstIndex(where: { $0.id == key(date) }) { entries[index].isSample = true }
        }
        do {
            try persist()
            UserDefaults.standard.set(true, forKey: "seededSkySamplesV1")
        } catch { self.error = "Sample skies couldn’t be saved." }
    }
    func key(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
    func entry(_ date: Date) -> SkyEntry? { entries.first { $0.id == key(date) } }
    func image(_ entry: SkyEntry) -> UIImage? { UIImage(contentsOfFile: directory.appendingPathComponent(entry.id + ".jpg").path) }
    func persist() throws { try JSONEncoder().encode(entries).write(to: directory.appendingPathComponent("entries.json"), options: .atomic) }
    func save(_ image: UIImage, on date: Date) {
        let id = key(date)
        do {
            guard let data = image.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent(id + ".jpg"), options: .atomic)
            if entry(date) == nil { entries.append(SkyEntry(id: id, date: date, note: "")) }
            try persist()
        } catch { self.error = "This sky couldn’t be saved. Please try again." }
    }
    func update(_ id: String, note: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].note = note
        do { try persist() } catch { self.error = "Your note couldn’t be saved." }
    }
    func delete(_ id: String) {
        let previous = entries
        entries.removeAll { $0.id == id }
        do {
            try persist()
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".jpg"))
        } catch { entries = previous; self.error = "This sky couldn’t be deleted." }
    }
}

@main struct AboveApp: App {
    @StateObject private var store = SkyStore()
    var body: some Scene {
        WindowGroup { AboveRootView().environmentObject(store).preferredColorScheme(.light) }
    }
}

struct AboveRootView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    var body: some View {
        if hasSeenWelcome {
            CalendarView()
        } else {
            WelcomeView { withAnimation(.easeInOut(duration: 0.3)) { hasSeenWelcome = true } }
        }
    }
}

struct WelcomeView: View {
    let onContinue: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("above").font(.custom("BradleyHandITCTT-Bold", size: 26)).tracking(-1)
                    Spacer()
                    Button("Skip") { onContinue() }.font(.system(size: 15))
                }
                Spacer(minLength: 24)
                Text("We spend about 90% of our time indoors.")
                    .font(.system(size: geometry.size.height > 700 ? 43 : 35, weight: .medium))
                    .tracking(-1.8).lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("There’s still a sky above you.")
                    .font(.system(size: geometry.size.height > 700 ? 43 : 35, weight: .medium))
                    .tracking(-1.8).lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)
                Spacer(minLength: 24)
                Text("One photo. A little more looking up.")
                    .font(.system(size: 14)).padding(.bottom, 18)
                Button(action: onContinue) {
                    Text("Let’s look up ↗").font(.system(size: 22)).underline()
                        .padding(.vertical, 12)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 24)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .background(paper).foregroundStyle(.black)
        }
    }
}

struct CalendarView: View {
    @EnvironmentObject var store: SkyStore
    @State private var month = Date()
    @State private var captureDate = Date()
    @State private var selected: SkyEntry?
    @State private var camera = false
    private let calendar = Calendar.current
    var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    var days: [Date] {
        (calendar.range(of: .day, in: .month, for: month) ?? 1..<2).compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }
    var offset: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }
    var body: some View {
        GeometryReader { geometry in
            let photoSize = max(16, min((geometry.size.width - 104) / 7,
                                       (geometry.size.height - 410) / 6 - 32))
            VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("above").font(.custom("BradleyHandITCTT-Bold", size: 26)).tracking(-1)
                        Spacer()
                    }.padding(.bottom, geometry.size.height > 700 ? 38 : 16)
                    Text(month.formatted(.dateTime.month(.wide)).lowercased())
                        .font(.system(size: geometry.size.height > 650 ? 88 : 68, weight: .bold)).kerning(-4)
                        .minimumScaleFactor(0.45).lineLimit(1)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: geometry.size.height > 650 ? 106 : 82, alignment: .bottomLeading)
                        .layoutPriority(1).accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline) {
                        Text("A little more looking up.").font(.system(size: 15))
                        Spacer()
                        Text(month.formatted(.dateTime.year())).font(.system(size: 13))
                    }.frame(height: 20).padding(.top, 6)
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous month")
                        Spacer()
                        Button { month = Date() } label: { Text("Today").font(.system(size: 12)) }
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "arrow.right").frame(width: 44, height: 44) }.accessibilityLabel("Next month")
                    }.padding(.top, 16).padding(.bottom, 8)
                    skyGrid(photoSize: photoSize)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 112)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button { openCamera(on: Date()) } label: {
                                Text("Look up ↗")
                                    .font(.system(size: 22, weight: .regular))
                                    .underline()
                                    .fixedSize()
                                    .frame(height: 52, alignment: .leading)
                            }.buttonStyle(.plain)
                            Spacer()
                        }.frame(height: 52)
                        Text("One sky. Every day.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(height: 14, alignment: .leading)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 14)
                }
                .background(paper)
        }
        .foregroundStyle(.black)
        .fullScreenCover(isPresented: $camera) { CameraView { image in store.save(image, on: captureDate) } }
        .fullScreenCover(item: $selected) { entry in
            NavigationStack {
                EntryView(entry: entry).environmentObject(store)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func openCamera(on date: Date) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            store.error = "Camera is unavailable on this device. Use Above on an iPhone to take a sky photo."
            return
        }
        captureDate = date
        camera = true
    }
    var calendarGrid: some View { skyGrid(photoSize: 42) }
    func skyGrid(photoSize: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 10)
            }
            ForEach(-offset..<0, id: \.self) { _ in Color.clear.frame(height: photoSize + 20) }
            ForEach(days, id: \.self) { day in
                Button {
                    if let entry = store.entry(day) { selected = entry }
                    else { openCamera(on: day) }
                } label: {
                    VStack(spacing: 7) {
                        GeometryReader { proxy in
                            if let entry = store.entry(day), let image = store.image(entry) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.width).clipShape(Circle())
                            } else if calendar.isDateInToday(day) {
                                Circle().stroke(.black, lineWidth: 1).overlay(Image(systemName: "plus").font(.system(size: 15, weight: .light)))
                            } else { Color.clear }
                        }.frame(width: photoSize, height: photoSize)
                        Text("\(calendar.component(.day, from: day))").font(.system(size: 11))
                            .foregroundStyle(day > Date() ? .secondary : .primary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(calendar.startOfDay(for: day) > calendar.startOfDay(for: Date()))
                    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(store.entry(day) == nil ? "no photo" : "sky saved")")
            }
        }
    }
    func move(_ amount: Int) { month = calendar.date(byAdding: .month, value: amount, to: monthStart)! }
}

struct EntryView: View {
    @EnvironmentObject var store: SkyStore
    @Environment(\.dismiss) var dismiss
    let entry: SkyEntry
    @State private var confirmDelete = false
    @State private var draft = ""
    @State private var restingHeight: CGFloat = 0
    @FocusState private var noteFocused: Bool
    var savedNote: String { store.entries.first(where: { $0.id == entry.id })?.note ?? "" }
    func saveNote() {
        store.update(entry.id, note: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        if store.error == nil { noteFocused = false }
    }
    var body: some View {
        GeometryReader { geometry in
            let pageHeight = restingHeight > 0 ? restingHeight : geometry.size.height
            let side = max(0, min(geometry.size.width - 56, pageHeight * 0.48))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "arrow.left")
                                .frame(width: 44, height: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }.accessibilityLabel("Back")
                        Spacer()
                        Button { confirmDelete = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }.accessibilityLabel("Delete photo")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.date.formatted(.dateTime.month(.wide).day()).lowercased())
                            .font(.system(size: 34, weight: .bold)).tracking(-1.4)
                        Text("\(entry.date.formatted(.dateTime.weekday(.wide))), \(entry.date.formatted(.dateTime.year()))")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.frame(height: 144, alignment: .top)
                    Image(uiImage: store.image(entry) ?? UIImage())
                        .resizable().scaledToFill()
                        .frame(width: side, height: side).clipShape(Circle())
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(entry.isSample == true ? "Sample sky, AI-generated" : "Your sky photo")
                        .padding(.top, max(24, (pageHeight - side) / 2 - 156))
                    ZStack(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("A few words about this sky…")
                                .font(.system(size: 21)).foregroundStyle(.tertiary)
                                .padding(.top, 8).allowsHitTesting(false)
                        }
                        InlineNoteInput(text: $draft,
                                        focused: Binding(get: { noteFocused }, set: { noteFocused = $0 }),
                                        onDone: saveNote)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.top, max(32, (pageHeight - side) / 2 - 112))
                }
                .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: pageHeight, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { restingHeight = geometry.size.height }
            .onChange(of: geometry.size.height) { _, height in
                if !noteFocused && height > restingHeight { restingHeight = height }
            }
        }
        .background(paper).foregroundStyle(.black)
        .onAppear { draft = savedNote }
        .onChange(of: noteFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { saveNote() }
        }
        .onDisappear { if draft != savedNote { saveNote() } }
        .confirmationDialog("Delete this sky?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) { store.delete(entry.id); dismiss() }
        }
        .alert("Couldn’t save note", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct InlineNoteInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var onDone: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: 21)
        view.backgroundColor = .clear
        view.textColor = .black
        view.tintColor = .black
        view.isScrollEnabled = false
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.returnKeyType = .done
        view.accessibilityLabel = "Your note"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        if !focused && view.isFirstResponder { view.resignFirstResponder() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, size.height))
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: InlineNoteInput
        init(_ parent: InlineNoteInput) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.focused = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.focused = false }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onDone()
                textView.resignFirstResponder()
                return false
            }
            return true
        }
    }
}

@MainActor final class SkyCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "above.camera")
    @Published var ready = false
    @Published var takingPhoto = false
    @Published var message: String?
    var onCapture: ((UIImage) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.configure() }
                    else { self.message = "Allow camera access in Settings to collect your sky." }
                }
            }
        default: message = "Allow camera access in Settings to collect your sky."
        }
    }
    private func configure() {
        guard session.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            message = "A camera is needed to capture your sky. Try Above on your iPhone."
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            message = "The camera couldn’t start. Please try again."
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        let session = session
        queue.async { session.startRunning() }
        ready = true
    }
    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
    func shoot() {
        guard ready, !takingPhoto else { return }
        takingPhoto = true
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            self.takingPhoto = false
            guard error == nil, let data, let image = UIImage(data: data) else {
                self.message = "This photo couldn’t be captured. Please try again."
                return
            }
            // Normalize orientation and retain the center square seen by the circular preview.
            let side = min(image.size.width, image.size.height)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let crop = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                image.draw(at: CGPoint(x: (side - image.size.width) / 2, y: (side - image.size.height) / 2))
            }
            self.onCapture?(crop)
        }
    }
}

final class CameraPreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
struct RoundCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraPreviewSurface {
        let view = CameraPreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: CameraPreviewSurface, context: Context) {}
}
struct CameraView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var camera = SkyCamera()
    let onCapture: (UIImage) -> Void
    var body: some View {
        GeometryReader { geometry in
            let side = max(0, min(geometry.size.width - 56, geometry.size.height * 0.48))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left").frame(width: 44, height: 44)
                    }.accessibilityLabel("Back")
                    Spacer()
                    Text("above").font(.custom("BradleyHandITCTT-Bold", size: 26)).tracking(-1)
                }
                Spacer(minLength: 20)
                ZStack {
                    Circle().fill(Color.black.opacity(0.05))
                    RoundCameraPreview(session: camera.session).clipShape(Circle())
                    if let message = camera.message {
                        Text(message).font(.system(size: 15)).multilineTextAlignment(.center).padding(40)
                    }
                }
                .frame(width: side, height: side)
                .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                .frame(maxWidth: .infinity)
                Spacer(minLength: 20)
                Text("Take a moment to look up.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 20)
                Button { camera.shoot() } label: {
                    Circle().stroke(.black, lineWidth: 1.5)
                        .overlay(Circle().fill(.black).padding(7))
                        .overlay { if camera.takingPhoto { ProgressView().tint(.white) } }
                        .frame(width: 70, height: 70)
                }
                .buttonStyle(.plain).disabled(!camera.ready || camera.takingPhoto)
                .opacity(camera.ready ? 1 : 0.3)
                .accessibilityLabel("Take sky photo")
                .frame(maxWidth: .infinity)
                Spacer(minLength: 18)
            }
            .padding(.horizontal, 28).padding(.top, 12)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(paper).foregroundStyle(.black)
        }
        .onAppear {
            camera.onCapture = { image in onCapture(image); dismiss() }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }
}
