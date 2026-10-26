import SwiftUI
import Photos
import UIKit
@preconcurrency import AVFoundation
import ImageIO
import UserNotifications

private let backgroundPalette: [(String, Color)] = [
    ("Paper", Color(red: 0.985, green: 0.98, blue: 0.965)),
    ("Blue", Color(red: 0.88, green: 0.91, blue: 0.98)),
    ("Pink", Color(red: 0.85, green: 0.78, blue: 0.79)),
    ("Mint", Color(red: 0.86, green: 0.95, blue: 0.90)),
    ("Green", Color(red: 0.87, green: 0.93, blue: 0.84)),
    ("Yellow", Color(red: 1.0, green: 0.985, blue: 0.84))
]
private let inkPalette: [(String, Color)] = [
    ("Black", .black),
    ("Blue", Color(red: 0.16, green: 0.32, blue: 0.64)),
    ("Pink", Color(red: 0.89, green: 0.22, blue: 0.43)),
    ("Mint", Color(red: 0.16, green: 0.47, blue: 0.40)),
    ("Green", Color(red: 0.36, green: 0.72, blue: 0.46)),
    ("Red", Color(red: 0.74, green: 0.12, blue: 0.17)),
    ("Brown", Color(red: 0.34, green: 0.26, blue: 0.16))
]
private var appInk: Color {
    inkPalette.first { $0.0 == UserDefaults.standard.string(forKey: "inkPalette") }?.1 ?? .black
}
private var paper: Color {
    backgroundPalette.first { $0.0 == UserDefaults.standard.string(forKey: "backgroundPalette") }?.1 ?? backgroundPalette[0].1
}

private func emptySkyColor(grayAmount: CGFloat = 0.09) -> Color {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(paper).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let gray: CGFloat = 0.58
    return Color(red: Double(red * (1 - grayAmount) + gray * grayAmount),
                 green: Double(green * (1 - grayAmount) + gray * grayAmount),
                 blue: Double(blue * (1 - grayAmount) + gray * grayAmount))
}

struct SkyEntry: Codable, Identifiable {
    var id: String
    var date: Date
    var note: String
    var isSample: Bool? = nil
    var isGIF: Bool? = nil
}

@MainActor final class SkyReminder {
    static let shared = SkyReminder()
    private var updateTask: Task<Void, Never>?
    private let prefix = "above.sky."

    func refresh(entries: [SkyEntry]) {
        let previous = updateTask
        previous?.cancel()
        updateTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            guard UserDefaults.standard.bool(forKey: "skyReminderEnabled"), !Task.isCancelled else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let defaults = UserDefaults.standard
            let hour = defaults.object(forKey: "skyReminderHour") as? Int ?? 18
            let minute = defaults.integer(forKey: "skyReminderMinute")
            let calendar = Calendar.current
            let now = Date()
            // Reserve four of iOS's 64 pending notification slots for other app uses.
            for offset in 0..<60 {
                guard !Task.isCancelled,
                      let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                      let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      fireDate > now,
                      !entries.contains(where: { $0.isSample != true && calendar.isDate($0.date, inSameDayAs: day) }) else { continue }
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let identifier = "\(prefix)\(parts.year!)-\(parts.month!)-\(parts.day!)"
                let content = UNMutableNotificationContent()
                content.title = "A moment above."
                content.body = "You haven’t captured today’s sky yet. Take a moment to look up."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) }
                catch { return }
            }
        }
    }
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
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--sample-skies") { seedSamples() }
        #endif
        SkyReminder.shared.refresh(entries: entries)
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
    func persist() throws {
        try JSONEncoder().encode(entries).write(to: directory.appendingPathComponent("entries.json"), options: .atomic)
        SkyReminder.shared.refresh(entries: entries)
    }
    func save(_ image: UIImage, on date: Date) {
        let id = key(date)
        do {
            guard let data = image.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent(id + ".jpg"), options: .atomic)
            if entry(date) == nil { entries.append(SkyEntry(id: id, date: date, note: "")) }
            try persist()
        } catch { self.error = "This sky couldn’t be saved. Please try again." }
    }
    func gifURL(_ entry: SkyEntry) -> URL? {
        guard entry.isGIF == true else { return nil }
        return directory.appendingPathComponent(entry.id + ".gif")
    }
    @discardableResult func saveGIF(_ source: URL, on date: Date) -> Bool {
        let id = key(date)
        let previous = entries
        let gif = directory.appendingPathComponent(id + ".gif")
        let poster = directory.appendingPathComponent(id + ".jpg")
        let oldGIF = try? Data(contentsOf: gif)
        let oldPoster = try? Data(contentsOf: poster)
        do {
            let data = try Data(contentsOf: source)
            guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try data.write(to: gif, options: .atomic)
            try jpeg.write(to: poster, options: .atomic)
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].isGIF = true
                entries[index].isSample = false
            } else {
                entries.append(SkyEntry(id: id, date: date, note: "", isGIF: true))
            }
            try persist()
            return true
        } catch {
            entries = previous
            if let oldGIF { try? oldGIF.write(to: gif, options: .atomic) } else { try? FileManager.default.removeItem(at: gif) }
            if let oldPoster { try? oldPoster.write(to: poster, options: .atomic) } else { try? FileManager.default.removeItem(at: poster) }
            self.error = "This sky couldn’t be saved. Please try again."
            return false
        }
    }
    func saveCopyToPhotos(_ url: URL, date: Date) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "Your sky is saved in Above. Allow Photos access in Settings to save a copy there."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = date
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "Above-\(url.lastPathComponent)"
                options.uniformTypeIdentifier = "com.compuserve.gif"
                request.addResource(with: .photo, fileURL: url, options: options)
            }
        } catch {
            self.error = "Your sky is saved in Above, but the copy couldn’t be saved to Photos."
        }
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
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".gif"))
        } catch { entries = previous; self.error = "This sky couldn’t be deleted." }
    }
}

@main struct AboveApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("backgroundPalette") private var backgroundChoice = "Paper"
    @AppStorage("inkPalette") private var inkChoice = "Black"
    @StateObject private var store = SkyStore()
    var body: some Scene {
        WindowGroup { AboveRootView().background((backgroundPalette.first { $0.0 == backgroundChoice }?.1 ?? paper).ignoresSafeArea()).tint(inkPalette.first { $0.0 == inkChoice }?.1 ?? appInk).environmentObject(store).preferredColorScheme(.light)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { SkyReminder.shared.refresh(entries: store.entries) }
            }
        }
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
                    Text("Above").font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                Spacer(minLength: 24)
                Text("We spend about 90% of our time indoors.")
                    .font(.system(size: geometry.size.height > 700 ? 43 : 35, weight: .medium))
                    .tracking(-1.8).lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Outside, the clouds keep moving.")
                    .font(.system(size: geometry.size.height > 700 ? 43 : 35, weight: .medium))
                    .tracking(-1.8).lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)
                Spacer(minLength: 24)
                Text("Take ten seconds to notice.")
                    .font(.system(size: 14)).padding(.bottom, 2)
                Button(action: onContinue) {
                    Text("Let’s look up ↗").font(.system(size: 22)).underline()
                        .padding(.vertical, 12)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 24)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .background(paper).foregroundStyle(appInk)
        }
    }
}

struct CalendarView: View {
    @EnvironmentObject var store: SkyStore
    @State private var month = Date()
    @State private var yearView = true
    @State private var showingMonthStyles = false
    @State private var showingSettings = false
    @AppStorage("backgroundPalette") private var backgroundChoice = "Paper"
    @AppStorage("inkPalette") private var inkChoice = "Black"
    @AppStorage("monthlyCalendarStyle") private var monthlyStyle = "Poster"
    private var calendarStyle: String { yearView ? "Year" : monthlyStyle }
    @State private var captureDate = Date()
    @AppStorage("photosCopyPreference") private var photosCopyPreference = "unasked"
    @State private var pendingPhotosCopy: URL?
    @State private var pendingPhotosDate = Date()
    @State private var showPhotosChoice = false
    @State private var selected: SkyEntry?
    @State private var camera = false
    @State private var today = Date()
    private let calendar = Calendar.current
    var headerImage: UIImage? {
        store.entry(today).flatMap { store.image($0) }
    }
    var hasSky: Bool { calendarStyle == "Month v2" }
    var wordmark: some View {
        Button {
            showingMonthStyles = false
            showingSettings = true
        } label: {
            Text("Above").font(.system(size: 12, weight: .semibold))
        }
        .accessibilityLabel("Above settings")
            #if targetEnvironment(simulator)
            .contextMenu {
                Button("Preview introduction") {
                    UserDefaults.standard.set(false, forKey: "hasSeenWelcome")
                }
            }
            #endif
    }
    var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    var days: [Date] {
        (calendar.range(of: .day, in: .month, for: month) ?? 1..<2).compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }
    var offset: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }
    var body: some View {
        Group {
        if yearView {
            yearlyCalendar
        } else if calendarStyle == "Poster" {
            graphicCalendar(blocks: false)
        } else if calendarStyle == "Notebook" {
            notebookCalendar
        } else if calendarStyle == "Month v1" {
            classicCalendar
        } else {
        GeometryReader { geometry in
            let photoSize = max(20, min((geometry.size.width - 50) / 7,
                                       (geometry.size.height - 290) / 6 - 4))
            let reservedRows = 6
            let gridHeight = 23 + CGFloat(reservedRows) * (photoSize + 4) + CGFloat(reservedRows - 1) * 5
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let capturedHeaderHeight = max(120, min(geometry.size.width - 32, geometry.size.height - gridHeight - 140)) + 64
            let emptyHeaderHeight = max(52, geometry.size.height - gridHeight - 250 - 32 - fullHeight * 0.05)
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { header in
                    let image = headerImage
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 48)
                        Group {
                            if let image {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                ZStack {
                                    LinearGradient(
                                        colors: [emptySkyColor(grayAmount: 0.13),
                                                 emptySkyColor(grayAmount: 0.06)],
                                        startPoint: .top, endPoint: .bottom)
                                    Text("Today’s sky is waiting.")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(Color(red: 0.59, green: 0.61, blue: 0.63))
                                        .multilineTextAlignment(.center)
                                        .padding(24)
                                }
                            }
                        }
                        .frame(width: header.size.width, height: max(0, header.size.height - 64))
                        .clipped()
                        .accessibilityLabel(headerImage == nil ? "Today’s sky is waiting." : "Today’s captured sky")
                        Color.clear.frame(height: 16)
                    }
                }
                .frame(height: hasSky ? capturedHeaderHeight : emptyHeaderHeight)
                .frame(minHeight: 52)
                HStack(spacing: 12) {
                    if hasSky {
                        Text(month.formatted(.dateTime.month(.wide)))
                            .font(.system(size: 24, weight: .medium)).tracking(-0.4)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button { move(-1) } label: {
                            Image(systemName: "chevron.left").font(.system(size: 17, weight: .regular)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Previous month")
                        Button { move(1) } label: {
                            Image(systemName: "chevron.right").font(.system(size: 17, weight: .regular)).frame(width: 44, height: 44, alignment: .trailing)
                        }.accessibilityLabel("Next month")
                    } else {
                        Button { move(-1) } label: {
                            Image(systemName: "arrow.left").frame(width: 44, height: 44, alignment: .leading)
                        }.accessibilityLabel("Previous month")
                        Spacer()
                        Button { month = Date() } label: { Text("Today").font(.system(size: 12, weight: .semibold)) }
                        Spacer()
                        Button { move(1) } label: {
                            Image(systemName: "arrow.right").frame(width: 44, height: 44, alignment: .trailing)
                        }.accessibilityLabel("Next month")
                    }
                }.padding(.top, 12).padding(.bottom, 12)
                skyGrid(photoSize: photoSize, width: geometry.size.width - 32)
                    .frame(height: hasSky ? gridHeight : nil, alignment: .top)
                if !hasSky {
                VStack(alignment: .leading, spacing: 12) {
                    Text(month.formatted(.dateTime.month(.wide)).lowercased())
                        .font(.system(size: 78, weight: .bold)).kerning(-4)
                        .minimumScaleFactor(0.45).lineLimit(1)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 94, alignment: .bottomLeading)
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .top, spacing: 16) {
                        Text(month.formatted(.dateTime.year()))
                        Spacer(minLength: 4)
                        Text("a little sky to keep\nevery day.")
                            .font(.system(size: 16, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        EditorialStarburst().fill(appInk).frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 16, weight: .bold))
                    .frame(height: 40, alignment: .top)
                }
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 22)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(paper)
        }
        }
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if showingMonthStyles {
                    Color.black.opacity(0.001).contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.16)) { showingMonthStyles = false } }
                        .accessibilityLabel("Close month designs")
                        .accessibilityAddTraits(.isButton)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 14) {
                        Button {
                            yearView = true
                            showingMonthStyles = false
                        } label: {
                            Text("Year").fontWeight(yearView ? .semibold : .regular)
                                .opacity(yearView ? 1 : 0.5)
                        }
                        .accessibilityAddTraits(yearView ? .isSelected : [])
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { showingMonthStyles.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Month")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .rotationEffect(.degrees(showingMonthStyles ? 180 : 0))
                            }
                            .fontWeight(yearView ? .regular : .semibold)
                            .opacity(yearView && !showingMonthStyles ? 0.5 : 1)
                        }
                        .accessibilityLabel("Month designs")
                        .accessibilityValue(showingMonthStyles ? "Expanded" : "Collapsed")
                        .accessibilityAddTraits(yearView ? [] : .isSelected)
                        Spacer()
                        wordmark
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(appInk)
                    .frame(height: 44)
                    if showingMonthStyles {
                        VStack(spacing: 0) {
                            ForEach(Array(["Classic", "Sky", "Poster", "Notebook"].enumerated()), id: \.offset) { index, name in
                                let style = name == "Classic" ? "Month v1" : name == "Sky" ? "Month v2" : name
                                Button {
                                    monthlyStyle = style
                                    yearView = false
                                    withAnimation(.easeOut(duration: 0.16)) { showingMonthStyles = false }
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                        Text(name).font(.system(size: 12, weight: .semibold))
                                        Spacer()
                                        if monthlyStyle == style {
                                            Circle().fill(appInk).frame(width: 6, height: 6)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(monthlyStyle == style ? .isSelected : [])
                                if index < 3 {
                                    Rectangle().fill(appInk.opacity(0.12)).frame(height: 0.5)
                                }
                            }
                        }
                        .foregroundStyle(appInk)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, showingMonthStyles ? 16 : 0)
                .background { if showingMonthStyles { paper } }
            }
        }
        .foregroundStyle(appInk)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { today = $0 }
        .fullScreenCover(isPresented: $showingSettings) { StorageSettingsView() }
        .fullScreenCover(isPresented: $camera, onDismiss: {
            guard let url = pendingPhotosCopy else { return }
            if photosCopyPreference == "unasked" {
                showPhotosChoice = true
            } else if photosCopyPreference == "enabled" {
                let date = pendingPhotosDate
                pendingPhotosCopy = nil
                Task { await store.saveCopyToPhotos(url, date: date) }
            } else {
                pendingPhotosCopy = nil
            }
        }) {
            CameraView { url in
                guard calendar.isDateInToday(captureDate),
                      store.saveGIF(url, on: captureDate) else { return false }
                pendingPhotosCopy = store.directory.appendingPathComponent(store.key(captureDate) + ".gif")
                pendingPhotosDate = captureDate
                return true
            }
        }
        .alert("Keep a copy in Photos?", isPresented: $showPhotosChoice) {
            Button("Save to Photos") {
                photosCopyPreference = "enabled"
                if let url = pendingPhotosCopy {
                    let date = pendingPhotosDate
                    pendingPhotosCopy = nil
                    Task { await store.saveCopyToPhotos(url, date: date) }
                }
            }
            Button("Keep in Above", role: .cancel) {
                photosCopyPreference = "disabled"
                pendingPhotosCopy = nil
            }
        } message: {
            Text("Your skies are saved in Above. Save a copy to Photos, too. Your choice will apply to future skies.")
        }
        .fullScreenCover(item: $selected) { entry in
            NavigationStack {
                EntryView(entry: entry).environmentObject(store)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    var classicCalendar: some View {
        GeometryReader { geometry in
            let background = paper
            let ink = appInk
            let width = geometry.size.width - 32
            let circleSize = max(20, min((geometry.size.width - 50) / 7,
                                         (geometry.size.height - 290) / 6 - 4))
            let focus = calendar.isDate(month, equalTo: today, toGranularity: .month) ? today : monthStart
            let daySize = min(width * 0.42, geometry.size.height * 0.21)
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: max(42, geometry.size.height * 0.075))
                Text(focus.formatted(.dateTime.day()))
                    .font(.system(size: daySize, weight: .bold))
                    .lineLimit(1)
                    .padding(.bottom, 12)
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.system(size: width * 0.075, weight: .medium))
                    .tracking(0.5)
                HStack(alignment: .firstTextBaseline) {
                    Text(month.formatted(.dateTime.year())).foregroundStyle(ink.opacity(0.48))
                    Spacer()
                    Text(focus.formatted(.dateTime.weekday(.abbreviated)))
                }
                .font(.system(size: width * 0.075, weight: .regular))
                .padding(.top, 2)
                HStack(spacing: 8) {
                    Button { move(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .medium))
                            .frame(width: 40, height: 44, alignment: .leading)
                    }.accessibilityLabel("Previous month")
                    Button { move(1) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium))
                            .frame(width: 40, height: 44, alignment: .leading)
                    }.accessibilityLabel("Next month")
                }
                .padding(.top, 18)
                Color.clear.frame(height: 20)
                classicDateGrid(width: width, circleSize: circleSize)
                    .frame(height: 23 + 6 * (circleSize + 4) + 5 * 5, alignment: .top)
                Spacer(minLength: 20)

            }
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(background.ignoresSafeArea())
        }
    }

    func classicDateGrid(width: CGFloat, circleSize: CGFloat) -> some View {
        let cell = width / 7
        let rows = (offset + days.count + 6) / 7
        let ink = appInk
        return VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, name in
                        Text(name).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ink.opacity(0.5))
                            .frame(width: circleSize).frame(width: cell, alignment: .leading)
                    }
                }
                .padding(.bottom, 10)
                VStack(spacing: 5) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { column in
                                let index = row * 7 + column - offset
                                if index >= 0 && index < days.count {
                                    let day = days[index]
                                    let current = calendar.isDate(day, inSameDayAs: today)
                                    Button {
                                        if let entry = store.entry(day) { selected = entry }
                                        else { openCamera(on: day) }
                                    } label: {
                                        ZStack {
                                            Circle().fill(emptySkyColor())
                                            if let entry = store.entry(day), let image = store.image(entry) {
                                                Image(uiImage: image).resizable().scaledToFill().clipShape(Circle())
                                            } else if current {
                                                Image(systemName: "plus")
                                                    .font(.system(size: cell * 0.46, weight: .light))
                                                    .foregroundStyle(ink)
                                            }
                                        }
                                        .frame(width: circleSize, height: circleSize)
                                        .overlay {
                                            if current { Circle().strokeBorder(ink, lineWidth: 1) }
                                        }
                                        .frame(width: cell, height: circleSize + 4, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!calendar.isDateInToday(day) && store.entry(day) == nil)
                                    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(current ? "today, " : "")\(store.entry(day) == nil ? "no sky" : "sky saved")")
                                } else {
                                    Color.clear.frame(width: cell, height: circleSize + 4, alignment: .leading)
                                }
                            }
                        }
                    }
                }
        }
    }

    var notebookCalendar: some View {
        GeometryReader { geometry in
            let blue = Color(red: 0.12, green: 0.40, blue: 0.73)
            let rule = Color(red: 0.80, green: 0.36, blue: 0.22)
            let width = geometry.size.width - 32
            let cell = width / 7
            VStack(spacing: 0) {
                Color.clear.frame(height: 64)
                Path { path in
                    let step = (width - 10) / 28
                    path.move(to: CGPoint(x: 0, y: 17))
                    for index in 0..<28 {
                        let x = CGFloat(index) * step
                        let wobble: CGFloat = index % 3 == 0 ? 1 : -0.5
                        path.addCurve(to: CGPoint(x: x + step * 0.5, y: 3 + wobble),
                                      control1: CGPoint(x: x - step * 0.25, y: 4),
                                      control2: CGPoint(x: x + step * 0.15, y: -1))
                        path.addCurve(to: CGPoint(x: x + step, y: 17),
                                      control1: CGPoint(x: x + step * 0.95, y: 7),
                                      control2: CGPoint(x: x + step * 1.1, y: 21))
                    }
                }
                .stroke(Color(red: 0.24, green: 0.43, blue: 0.28),
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(height: 20)
                .padding(.horizontal, 5).padding(.bottom, 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(month.formatted(.dateTime.month(.twoDigits)))
                        .tracking(-5)
                    Spacer(minLength: 0)
                    Text(month.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .tracking(-4)
                }
                .font(.system(size: width * 0.23, weight: .regular))
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, 6).padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 0.8) }
                HStack(spacing: 0) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, title in
                        Text(title).font(.system(size: 20, weight: .regular)).padding(.leading, 6)
                            .frame(width: cell, height: 34, alignment: .leading)
                            .overlay { Rectangle().stroke(rule, lineWidth: 0.4) }
                    }
                }
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column - offset
                            ZStack(alignment: .topLeading) {
                                if index >= 0 && index < days.count {
                                    let day = days[index]
                                    Button {
                                        if let entry = store.entry(day) { selected = entry }
                                        else { openCamera(on: day) }
                                    } label: {
                                        ZStack(alignment: .topLeading) {
                                            if let entry = store.entry(day), let image = store.image(entry) {
                                                Image(uiImage: image).resizable().scaledToFill()
                                                    .frame(width: cell, height: cell * 1.12).clipped()
                                            }
                                            if store.entry(day) == nil {
                                                Text("\(calendar.component(.day, from: day))")
                                                    .font(.system(size: 23, weight: .regular))
                                                    .foregroundStyle(blue)
                                                    .padding(.leading, 5).padding(.top, 3)
                                            }
                                            if calendar.isDateInToday(day) && store.entry(day) == nil {
                                                Image(systemName: "plus").font(.system(size: 17, weight: .light))
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                                    .padding(7)
                                            }
                                        }.frame(width: cell, height: cell * 1.12, alignment: .topLeading)
                                    }.buttonStyle(.plain)
                                        .disabled(!calendar.isDateInToday(day) && store.entry(day) == nil)
                                        .accessibilityLabel(day.formatted(.dateTime.month().day()))
                                }
                            }.frame(width: cell, height: cell * 1.12)
                                .overlay { Rectangle().stroke(rule, lineWidth: 0.4).allowsHitTesting(false) }
                        }
                    }
                }
                .overlay { Color.clear }
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Spacer()
                    Text(month.formatted(.dateTime.year())).font(.system(size: 12))
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                }.font(.system(size: 14, weight: .regular)).padding(.top, 12)
                Spacer(minLength: 0)
            }
            .foregroundStyle(blue)
            .padding(.horizontal, 16)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(paper)
        }
    }

    func graphicCalendar(blocks: Bool) -> some View {
        GeometryReader { geometry in
            let side = (geometry.size.width - 44) / 7
            let weekCount = (offset + days.count + 6) / 7
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: blocks ? 36 : 16 + geometry.size.height * 0.10)
                if blocks {
                HStack {
                    Text(month.formatted(.dateTime.month(.twoDigits)))
                        .font(.system(size: blocks ? 110 : 51.2, weight: blocks ? .black : .medium)).tracking(blocks ? -5 : -2)
                    Spacer()
                    Text("’" + String(calendar.component(.year, from: month) % 100))
                        .font(.system(size: blocks ? 24 : 51.2, weight: blocks ? .bold : .medium)).tracking(-2)
                }.frame(height: blocks ? 65 : 78).padding(.top, blocks ? 32 : 32)
                }
                if !blocks {
                    Rectangle().fill(appInk).frame(height: 1)
                        .padding(.horizontal, -8)
                    Color.clear.frame(height: 12)
                    Text(month.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: geometry.size.width * 0.47, weight: .bold))
                        .tracking(-geometry.size.width * 0.025)
                        .minimumScaleFactor(0.4).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .overlay {
                            HStack {
                                Button { move(-1) } label: { Color.clear.frame(width: 44, height: 80) }
                                    .accessibilityLabel("Previous month")
                                Spacer()
                                Button { move(1) } label: { Color.clear.frame(width: 44, height: 80) }
                                    .accessibilityLabel("Next month")
                            }
                        }

                    Rectangle().fill(appInk).frame(height: 1)
                        .padding(.horizontal, -8)
                }
                if blocks { Color.clear.frame(height: 16) }
                else { Color.clear.frame(height: 10) }
                HStack(spacing: 2) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, name in
                        Text(name).font(.system(size: blocks ? 10 : side * 0.8, weight: blocks ? .bold : .medium))
                            .frame(width: side)
                    }
                }.padding(.bottom, blocks ? 8 : 2)
                VStack(spacing: blocks ? 0 : 6) {
                    ForEach(0..<weekCount, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { column in
                                let index = row * 7 + column - offset
                                if index >= 0 && index < days.count {
                                    graphicDay(days[index], side: side, blocks: blocks)
                                } else {
                                    Color.clear.frame(width: side, height: side)
                                }
                            }
                        }
                        .background {
                            if blocks { Capsule().fill(appInk) }
                        }
                    }
                }
                if blocks {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44, alignment: .leading) }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    if blocks {
                        Text(month.formatted(.dateTime.month(.wide)).lowercased())
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44, alignment: .trailing) }
                        .accessibilityLabel("Next month")
                }.padding(.top, 18)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.bottom, 18)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(paper)
            .overlay {
                if !blocks {
                    Rectangle().strokeBorder(appInk, lineWidth: 1)
                        .padding(.top, 44)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 18)
                        .allowsHitTesting(false)
                }
            }
        }
    }
    func graphicDay(_ day: Date, side: CGFloat, blocks: Bool) -> some View {
        Button {
            if let entry = store.entry(day) { selected = entry }
            else { openCamera(on: day) }
        } label: {
            ZStack {
                if let entry = store.entry(day), let image = store.image(entry) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                if store.entry(day) == nil {
                if calendar.isDate(day, inSameDayAs: today) {
                    Image(systemName: "plus").font(.system(size: 25, weight: .regular))
                        .foregroundStyle(blocks ? .white : appInk)
                } else {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: blocks ? 10 : side * 0.8, weight: blocks ? .bold : .medium))
                    .tracking(blocks ? 0 : -side * 0.065)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(blocks || store.entry(day) != nil ? .white : appInk)
                    .shadow(color: store.entry(day) != nil ? .black.opacity(0.5) : .clear, radius: 2)
                }
                }
            }
            .frame(width: side - (blocks ? 1 : 0), height: side - (blocks ? 1 : 0))
            .clipShape(Circle())
            .overlay { if !blocks && calendar.isDateInToday(day) { Circle().stroke(blocks ? .white : .black, lineWidth: 1) } }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .disabled(!calendar.isDateInToday(day) && store.entry(day) == nil)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(store.entry(day) == nil ? "no sky" : "sky saved")")
    }
    var yearlyCalendar: some View {
        GeometryReader { geometry in
        let circleSize = min(22, max(14, (geometry.size.height - 140) / 27))
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 24)
            HStack {
                Text(month.formatted(.dateTime.year())).font(.system(size: 54, weight: .bold)).tracking(-2)
                Spacer()
                Button { moveYear(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous year")
                Button { moveYear(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next year")
            }.padding(.top, 6).offset(y: 10)
                Spacer(minLength: 0)
                YearFlowLayout(spacing: 1, rowSpacing: 3) {
                    ForEach(1...12, id: \.self) { number in
                        let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: month), month: number, day: 1))!
                        Text(start.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.system(size: 22, weight: .heavy)).tracking(-1)
                            .padding(.horizontal, 3).frame(height: 21)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(0..<(calendar.range(of: .day, in: .month, for: start)?.count ?? 0), id: \.self) { index in
                            let day = calendar.date(byAdding: .day, value: index, to: start)!
                            Button {
                                if let entry = store.entry(day) { selected = entry }
                                else { openCamera(on: day) }
                            } label: {
                                ZStack {
                                    if let entry = store.entry(day), let image = store.image(entry) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else if calendar.isDate(day, inSameDayAs: today) {
                                        Image(systemName: "plus").font(.system(size: 12, weight: .regular))
                                    } else {
                                        Text("\(index + 1)").font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(appInk.opacity(day > today ? 0.25 : 0.7))
                                    }
                                }
                                .frame(width: circleSize, height: circleSize).clipShape(Circle())
                                .overlay { if calendar.isDateInToday(day) { Circle().stroke(appInk, lineWidth: 1) } }
                                .frame(width: circleSize, height: circleSize)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!calendar.isDateInToday(day) && store.entry(day) == nil)
                            .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(store.entry(day) == nil ? "no sky" : "sky saved")")
                        }
                    }
                }
                Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        .background(paper)
        }
    }
    func moveYear(_ amount: Int) {
        month = calendar.date(byAdding: .year, value: amount, to: month)!
    }
    func openCamera(on date: Date) {
        guard calendar.isDateInToday(date) else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            store.error = "Camera is unavailable on this device. Use Above on an iPhone to record your sky."
            return
        }
        captureDate = date
        camera = true
    }
    func skyGrid(photoSize: CGFloat, width: CGFloat) -> some View {
        classicDateGrid(width: width, circleSize: photoSize)
    }
    func move(_ amount: Int) { month = calendar.date(byAdding: .month, value: amount, to: monthStart)! }
}

struct PaletteEditor: View {
    @AppStorage("backgroundPalette") private var backgroundChoice = "Paper"
    @AppStorage("inkPalette") private var inkChoice = "Black"
    @State private var draftBackground = "Paper"
    @State private var draftInk = "Black"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Palette").font(.system(size: 18, weight: .medium)).tracking(-0.4)
                Spacer()
                Button {
                    backgroundChoice = draftBackground
                    inkChoice = draftInk
                } label: {
                    Text("Save").font(.system(size: 13, weight: .medium))
                        .frame(height: 32)
                }.accessibilityLabel("Save colors")
                .disabled(draftBackground == backgroundChoice && draftInk == inkChoice)
                .opacity(draftBackground == backgroundChoice && draftInk == inkChoice ? 0.35 : 1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Aa").font(.system(size: 56, weight: .medium)).tracking(-3)
                Spacer()
                Text("Above").font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(inkPalette.first { $0.0 == draftInk }?.1 ?? .black).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(backgroundPalette.first { $0.0 == draftBackground }?.1 ?? backgroundPalette[0].1, in: RoundedRectangle(cornerRadius: 3))
            paletteRow("Background", palette: backgroundPalette, choice: $draftBackground)
            paletteRow("Type", palette: inkPalette, choice: $draftInk)
        }
        .foregroundStyle(appInk)
        .onAppear {
            draftBackground = backgroundChoice
            draftInk = inkChoice
        }
    }
    func paletteRow(_ title: String, palette: [(String, Color)], choice: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased()).font(.system(size: 10, weight: .medium)).tracking(1.2)
                Spacer()
                Text(choice.wrappedValue).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(palette, id: \.0) { name, color in
                    Button { choice.wrappedValue = name } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(color)
                                .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(.black.opacity(0.08), lineWidth: 0.5) }
                                .frame(height: 34)
                                .overlay {
                                    if choice.wrappedValue == name {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(title == "Background" || name == "Green" ? Color.black.opacity(0.8) : Color.white)
                                    }
                                }

                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(name)")
                    .accessibilityAddTraits(choice.wrappedValue == name ? .isSelected : [])
                }
            }
        }
    }
}

struct StorageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("photosCopyPreference") private var photosCopyPreference = "unasked"
    @EnvironmentObject private var store: SkyStore
    @AppStorage("skyReminderEnabled") private var reminderEnabled = false
    @AppStorage("skyReminderHour") private var reminderHour = 18
    @AppStorage("skyReminderMinute") private var reminderMinute = 0
    @State private var requestingReminder = false
    @State private var reminderDenied = false
    @State private var reminderError = false
    private var reminderTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            reminderHour = Calendar.current.component(.hour, from: date)
            reminderMinute = Calendar.current.component(.minute, from: date)
            SkyReminder.shared.refresh(entries: store.entries)
        })
    }
    @State private var checkingPermission = false
    @State private var permissionDenied = false
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").frame(width: 44, height: 44, alignment: .leading)
                }.accessibilityLabel("Back")
                Spacer()
                Text("Above").font(.system(size: 12, weight: .semibold))
            }
            Text("your skies.").font(.system(size: 36, weight: .bold)).tracking(-1)
                .padding(.top, 36).padding(.bottom, 32)
            PaletteEditor().padding(.bottom, 32)
            Rectangle().fill(appInk.opacity(0.15)).frame(height: 0.5)
            Toggle(isOn: Binding(get: { photosCopyPreference == "enabled" }, set: { enabled in
                if !enabled { photosCopyPreference = "disabled"; return }
                checkingPermission = true
                Task { @MainActor in
                    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    checkingPermission = false
                    if status == .authorized || status == .limited {
                        photosCopyPreference = "enabled"
                    } else {
                        photosCopyPreference = "disabled"
                        permissionDenied = true
                    }
                }
            })) {
                Text("Save a copy to Photos").font(.system(size: 16, weight: .semibold))
            }
            .tint(appInk).disabled(checkingPermission).padding(.vertical, 20)
            Rectangle().fill(appInk.opacity(0.15)).frame(height: 0.5)
            Text("New skies will also be saved to Photos as moving GIFs. Your existing records stay where they are.")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 18)
            Text("Your skies and notes are always saved in Above on this iPhone. Turning this off keeps future captures in Above only.")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 16)
            Rectangle().fill(appInk.opacity(0.15)).frame(height: 0.5).padding(.top, 28)
            Toggle(isOn: Binding(get: { reminderEnabled }, set: { enabled in
                if !enabled {
                    reminderEnabled = false
                    SkyReminder.shared.refresh(entries: store.entries)
                    return
                }
                requestingReminder = true
                Task { @MainActor in
                    defer { requestingReminder = false }
                    do {
                        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        reminderEnabled = allowed
                        if allowed { SkyReminder.shared.refresh(entries: store.entries) }
                        else { reminderDenied = true }
                    } catch { reminderError = true }
                }
            })) {
                Text("Daily sky reminder").font(.system(size: 16, weight: .semibold))
            }.tint(appInk).disabled(requestingReminder).padding(.vertical, 20)
            if reminderEnabled {
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .font(.system(size: 14)).tint(appInk)
            }
            Text("A gentle reminder if you haven’t recorded today’s sky. Saving your sky cancels that day’s reminder.")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 12)
            #if targetEnvironment(simulator)
            Button("Preview introduction") {
                UserDefaults.standard.set(false, forKey: "hasSeenWelcome")
                dismiss()
            }.font(.system(size: 13)).padding(.top, 24)
            #endif
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(paper).foregroundStyle(appInk)
        .alert("Allow notifications", isPresented: $reminderDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Enable notifications for Above in iPhone Settings to receive sky reminders.")
        }
        .alert("Couldn’t enable reminders", isPresented: $reminderError) {
            Button("OK", role: .cancel) { }
        } message: { Text("Please try again.") }
        .alert("Allow Photos access", isPresented: $permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Allow Above to add to Photos in Settings. Your records in Above are safe either way.")
        }
    }
}

struct EntryView: View {
    @EnvironmentObject var store: SkyStore
    @Environment(\.dismiss) var dismiss
    let entry: SkyEntry
    @State private var confirmDelete = false
    @State private var draft = ""
    @State private var restingHeight: CGFloat = 0
    @State private var noteFocused = false
    @State private var poster: UIImage?
    @State private var mediaURL: URL?
    var savedNote: String { store.entries.first(where: { $0.id == entry.id })?.note ?? "" }
    func saveNote() {
        store.update(entry.id, note: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        if store.error == nil { noteFocused = false }
    }
    var body: some View {
        GeometryReader { geometry in
            let pageHeight = restingHeight > 0 ? restingHeight : geometry.size.height
            let side = max(0, min(geometry.size.width - 56, pageHeight * 0.48))
            ScrollViewReader { scroll in
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
                                .font(.system(size: 15))
                                .frame(width: 44, height: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }.accessibilityLabel("Delete photo")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(entry.date.formatted(.dateTime.month(.wide).day())), \(entry.date.formatted(.dateTime.weekday(.wide)))")
                            .font(.system(size: 26, weight: .medium)).tracking(-0.6)
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                }.frame(height: 144, alignment: .top)
                    SkyMediaView(poster: poster, gifURL: mediaURL)
                        .frame(width: side, height: side).clipShape(Circle())
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(entry.isSample == true ? "Sample sky, AI-generated" : "Your sky photo")
                        .padding(.top, max(24, (pageHeight - side) / 2 - 156))
                    ZStack(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("leave a little thought…")
                                .font(.system(size: 21)).foregroundStyle(.tertiary)
                                .padding(.top, 8).allowsHitTesting(false)
                        }
                        InlineNoteInput(text: $draft,
                                        focused: Binding(get: { noteFocused }, set: { noteFocused = $0 }),
                                        onDone: saveNote)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.top, max(32, (pageHeight - side) / 2 - 112))
                    Color.clear.frame(height: 88).id("note")
                }
                .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: pageHeight, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard noteFocused else { return }
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeOut(duration: duration)) {
                    scroll.scrollTo("note", anchor: .bottom)
                }
            }
            .onAppear { restingHeight = geometry.size.height }
            .onChange(of: geometry.size.height) { _, height in
                if noteFocused && height < restingHeight {
                    // Reposition only after the keyboard has reduced the viewport;
                    // scrolling before that point is clamped to the old bounds.
                    withAnimation(.easeOut(duration: 0.25)) {
                        scroll.scrollTo("note", anchor: .bottom)
                    }
                } else if !noteFocused && height > restingHeight {
                    restingHeight = height
                }
            }
            }
        }
        .background(paper).foregroundStyle(appInk)
        .onAppear {
            draft = savedNote
            poster = store.image(entry)
            mediaURL = store.gifURL(entry)
        }
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
        view.textColor = UIColor(appInk)
        view.tintColor = UIColor(appInk)
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
        // UIKit owns responder changes; SwiftUI updates during keyboard presentation
        // must not dismiss an editing session using a stale focus value.
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

@MainActor final class SkyCamera: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "above.camera")
    private var cancelled = false
    private var conversion: Task<Void, Never>?
    private var clips: [URL] = []
    private var recordedSeconds: Double = 0
    @Published var paused = false
    @Published var finishingSegment = false
    @Published var ready = false
    @Published var recording = false
    @Published var processing = false
    @Published var startedAt: Date?
    @Published var message: String?
    var onCapture: ((URL) -> Void)?

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
        guard !cancelled, session.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            message = "A camera is needed to record your sky. Try Above on your iPhone."
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            message = "The camera couldn’t start. Please try again."
            return
        }
        session.addInput(input)
        // No audio input: the saved sky is a silent GIF.
        session.addOutput(output)
        output.maxRecordedDuration = CMTime(seconds: SkyGIFEncoder.duration, preferredTimescale: 600)
        session.commitConfiguration()
        let session = session
        queue.async {
            session.startRunning()
            Task { @MainActor in self.ready = session.isRunning && !self.cancelled }
        }
    }
    func stop() {
        cancelled = true
        ready = false
        conversion?.cancel()
        clips.forEach { try? FileManager.default.removeItem(at: $0) }
        clips.removeAll()
        if output.isRecording { output.stopRecording() }
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
    func interrupt() {
        guard recording || processing else { return }
        message = "That moment was interrupted. Tap the sky to start again."
        cancelled = true
        conversion?.cancel()
        clips.forEach { try? FileManager.default.removeItem(at: $0) }
        clips.removeAll()
        if output.isRecording { output.stopRecording() }
        startedAt = nil
        recording = false
        paused = false
        finishingSegment = false
    }
    func elapsed(at date: Date) -> Double {
        recordedSeconds + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }
    func record() {
        guard ready, !processing, !finishingSegment else { return }
        if recording && !paused {
            paused = true
            finishingSegment = true
            startedAt = nil
                output.stopRecording()
            return
        }
        if !recording {
            clips.forEach { try? FileManager.default.removeItem(at: $0) }
            clips.removeAll()
            recordedSeconds = 0
        }
        cancelled = false
        message = nil
        recording = true
        paused = false
        finishingSegment = true
        startedAt = nil
        output.maxRecordedDuration = CMTime(seconds: max(0.1, SkyGIFEncoder.duration - recordedSeconds), preferredTimescale: 600)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
            connection.preferredVideoStabilizationMode = .off
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        output.startRecording(to: url, recordingDelegate: self)
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in
            if self.cancelled { self.output.stopRecording() }
            else {
                self.startedAt = Date()
                self.finishingSegment = false
            }
        }
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        let completed = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        Task { @MainActor in
            self.finishingSegment = true
            defer { self.finishingSegment = false }
            guard !self.cancelled else { try? FileManager.default.removeItem(at: url); return }
            guard completed else {
                self.recording = false
                self.paused = false
                self.message = "The recording couldn’t finish. Tap the sky to try again."
                try? FileManager.default.removeItem(at: url)
                return
            }
            self.clips.append(url)
            let length = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard !self.cancelled else { return }
            self.recordedSeconds += length
            self.startedAt = nil
            if self.paused && self.recordedSeconds < SkyGIFEncoder.duration - 0.1 { return }
            self.recording = false
            self.paused = false
            self.processing = true
            let capturedClips = self.clips
            self.clips.removeAll()
            self.conversion = Task {
                defer {
                    self.processing = false
                    capturedClips.forEach { try? FileManager.default.removeItem(at: $0) }
                }
                do {
                    let gif = try await SkyGIFEncoder.encode(movieURLs: capturedClips)
                    defer { try? FileManager.default.removeItem(at: gif) }
                    guard !Task.isCancelled, !self.cancelled else { return }
                    self.onCapture?(gif)
                } catch is CancellationError { }
                catch { self.message = error.localizedDescription }
            }
        }
    }
}

/// Decode once per file; UIImageView plays the loop without rebuilding SwiftUI on each frame.
struct SkyMediaView: UIViewRepresentable {
    let poster: UIImage?
    let gifURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    final class Coordinator { var loadedURL: URL?; var reduceMotion = false }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        guard context.coordinator.loadedURL != gifURL || context.coordinator.reduceMotion != reduceMotion || view.image == nil else { return }
        context.coordinator.loadedURL = gifURL
        context.coordinator.reduceMotion = reduceMotion
        view.image = poster
        guard !reduceMotion, let gifURL, let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else { return }
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: frame))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            duration += gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.2
        }
        if !frames.isEmpty { view.image = UIImage.animatedImage(with: frames, duration: duration) }
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
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var camera = SkyCamera()
    let onCapture: (URL) -> Bool
    var body: some View {
        GeometryReader { geometry in
            let side = max(0, min(geometry.size.width - 40, geometry.size.height * 0.65))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { camera.stop(); dismiss() } label: {
                        Image(systemName: "arrow.left").frame(width: 44, height: 44, alignment: .leading)
                    }.accessibilityLabel("Back")
                    Spacer()
                    Text("Above").font(.system(size: 12, weight: .semibold))
                }
                Spacer(minLength: 20)
                Button { camera.record() } label: {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.05))
                        RoundCameraPreview(session: camera.session).clipShape(Circle())
                        if camera.processing { ProgressView().tint(.white).padding(16).background(.black.opacity(0.5), in: Circle()) }
                        if let message = camera.message {
                            Text(message).font(.system(size: 15)).multilineTextAlignment(.center)
                                .padding(30).background(paper.opacity(0.92), in: Circle())
                        } else if camera.paused {
                            Image(systemName: "pause.fill").font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.white).shadow(radius: 4)
                        } else if !camera.recording && !camera.processing {
                            Text("tap to keep a little sky")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 5, y: 1)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .frame(width: side, height: side)
                    .overlay {
                        TimelineView(.animation(paused: !camera.recording || camera.paused)) { context in
                            let elapsed = camera.elapsed(at: context.date)
                            let progress = camera.processing ? 1 : min(1, max(0, elapsed / SkyGIFEncoder.duration))
                            ZStack {
                                Circle().stroke(appInk.opacity(0.15), lineWidth: 2)
                                Circle().trim(from: 0, to: progress)
                                    .stroke(appInk, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }.padding(-8)
                        }.allowsHitTesting(false)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!camera.ready || camera.processing || camera.finishingSegment)
                .accessibilityLabel(camera.paused ? "Resume sky recording" : camera.recording ? "Pause sky recording" : "Record sky for ten seconds")
                .accessibilityHint("Tap to begin, pause, or resume. Ten seconds of recorded sky are saved automatically.")
                .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28).padding(.top, 12)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(paper).foregroundStyle(appInk)
        }
        .onAppear {
            camera.onCapture = { url in
                if onCapture(url) { dismiss() }
                else { camera.message = "This sky couldn’t be saved. Tap the circle to try again." }
            }
            camera.start()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { camera.interrupt() } }
        .onDisappear { camera.stop() }
    }
}

struct EditorialStarburst: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for index in 0..<24 {
            let angle = Double(index) * .pi / 12 - .pi / 2
            let r = radius * (index.isMultiple(of: 2) ? 1 : 0.48)
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}


struct YearFlowLayout: Layout {
    var spacing: CGFloat = 5
    var rowSpacing: CGFloat = 3
    func positions(width: CGFloat, subviews: Subviews) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(width: proposal.width ?? 360, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = positions(width: bounds.width, subviews: subviews).1
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + points[index].x, y: bounds.minY + points[index].y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// A compact, stepped wordmark with softly rounded pixel strokes.
struct AboveWordmark: View {
    var height: CGFloat = 20
    var body: some View {
        Text("Above")
            .font(.system(size: height, weight: .regular))
            .tracking(-height * 2 / 85)
            .accessibilityLabel("Above")
    }
}
