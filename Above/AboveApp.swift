import SwiftUI
import UIKit
@preconcurrency import AVFoundation
import ImageIO

private let paper = Color(white: 0.98)

struct SkyEntry: Codable, Identifiable {
    var id: String
    var date: Date
    var note: String
    var isSample: Bool? = nil
    var isGIF: Bool? = nil
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
                    AboveWordmark(height: 26)
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
                Text("Ten seconds. A little more looking up.")
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
    @State private var yearView = true
    @State private var calendarStyle = "Year"
    @State private var captureDate = Date()
    @State private var selected: SkyEntry?
    @State private var camera = false
    @State private var today = Date()
    #if targetEnvironment(simulator)
    @State private var previewSky: Bool? = true
    #endif
    private let calendar = Calendar.current
    var headerImage: UIImage? {
        #if targetEnvironment(simulator)
        if let previewSky {
            return previewSky ? Bundle.main.url(forResource: "blue", withExtension: "png", subdirectory: "DemoSkies").flatMap { UIImage(contentsOfFile: $0.path) } : nil
        }
        #endif
        return store.entry(today).flatMap { store.image($0) }
    }
    var hasSky: Bool { calendarStyle == "Month v2" }
    @ViewBuilder var wordmark: some View {
        #if targetEnvironment(simulator)
        Menu {
            Button("오늘 하늘 있음 · 샘플") { previewSky = true }
            Button("오늘 하늘 없음") { previewSky = false }
            Button("실제 저장된 하늘") { previewSky = nil }
        } label: {
            Text("above").font(.system(size: 12, weight: .semibold))
        }.accessibilityLabel("above, compare home versions")
        #else
        Text("above").font(.system(size: 12, weight: .semibold))
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
        } else {
        GeometryReader { geometry in
            let photoSize = max(20, min((geometry.size.width - 50) / 7,
                                       (geometry.size.height - 290) / 6 - 4))
            let rows = (offset + days.count + 6) / 7
            let gridHeight = 24 + CGFloat(rows) * photoSize + CGFloat(rows - 1) * 4
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let capturedHeaderHeight = max(52, geometry.size.height - gridHeight - 90)
            let emptyHeaderHeight = max(52, geometry.size.height - gridHeight - 250 - 32 - fullHeight * 0.05)
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { header in
                    Group {
                        let todayImage = hasSky ? headerImage : nil
                        ZStack(alignment: .topTrailing) {
                        ZStack {
                            paper
                            if let todayImage {
                                Image(uiImage: todayImage).resizable().scaledToFill()
                            }
                        }
                        .frame(width: header.size.width,
                               height: max(0, header.size.height + geometry.safeAreaInsets.top))
                        .clipped()
                        .offset(y: -geometry.safeAreaInsets.top)
                        .accessibilityLabel(todayImage == nil ? "Today’s sky, waiting to be captured" : "Today’s captured sky")
                        }.frame(width: header.size.width, height: header.size.height, alignment: .top)
                    }
                }
                .frame(height: hasSky ? capturedHeaderHeight : emptyHeaderHeight)
                .frame(minHeight: 52)
                .padding(.horizontal, -16)
                HStack(spacing: 12) {
                    if hasSky {
                        Text("\(month.formatted(.dateTime.month(.abbreviated)).lowercased()) ’\(String(format: "%02d", calendar.component(.year, from: month) % 100))")
                            .font(.system(size: 24, weight: .bold)).tracking(-0.8)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button { move(-1) } label: {
                            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Previous month")
                        Button { move(1) } label: {
                            Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44, alignment: .trailing)
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
                skyGrid(photoSize: photoSize)
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
                        EditorialStarburst().fill(.black).frame(width: 28, height: 28)
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
            HStack(spacing: 14) {
                // Monthly layouts remain implemented for future comparison.
                ForEach(["Year", "Month"], id: \.self) { option in
                    Button {
                        yearView = option == "Year"
                        calendarStyle = option == "Month" ? "Poster" : option
                    } label: {
                        Text(option).fontWeight((calendarStyle == option || (option == "Month" && calendarStyle == "Poster")) ? .semibold : .regular)
                            .opacity((calendarStyle == option || (option == "Month" && calendarStyle == "Poster")) ? 1 : 0.5)
                    }
                    .accessibilityAddTraits((calendarStyle == option || (option == "Month" && calendarStyle == "Poster")) ? .isSelected : [])
                }
                Spacer()
                wordmark
            }
            .font(.system(size: 12))
            .foregroundStyle(hasSky && headerImage != nil ? .white : .black)
            .padding(.horizontal, 16).padding(.top, 16)
        }
        .foregroundStyle(.black)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { today = $0 }
        .fullScreenCover(isPresented: $camera) { CameraView { url in store.saveGIF(url, on: captureDate) } }
        .fullScreenCover(item: $selected) { entry in
            NavigationStack {
                EntryView(entry: entry).environmentObject(store)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func graphicCalendar(blocks: Bool) -> some View {
        GeometryReader { geometry in
            let side = (geometry.size.width - 44) / 7
            let weekCount = (offset + days.count + 6) / 7
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 26).padding(.top, 46)
                HStack {
                    Text(month.formatted(.dateTime.month(.twoDigits)))
                        .font(.system(size: blocks ? 110 : 48, weight: .black)).tracking(-5)
                    Spacer()
                    Text("’" + String(calendar.component(.year, from: month) % 100))
                        .font(.system(size: blocks ? 24 : 48, weight: .bold)).tracking(-2)
                }.padding(.top, 18)
                if !blocks {
                    Rectangle().frame(height: 1).padding(.vertical, 12)
                    Text(month.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: 140, weight: .black)).tracking(-9)
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if blocks { Color.clear.frame(height: 16) }
                else { Spacer(minLength: 12) }
                HStack(spacing: 2) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, name in
                        Text(name).font(.system(size: blocks ? 10 : 25, weight: .bold))
                            .frame(width: side)
                    }
                }.padding(.bottom, blocks ? 8 : 12)
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
                            if blocks { Capsule().fill(.black) }
                        }
                    }
                }
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
                if blocks { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 16).padding(.bottom, 18)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(paper)
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
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: blocks ? 10 : 31, weight: .bold))
                    .foregroundStyle(blocks || store.entry(day) != nil ? .white : .black)
                    .shadow(color: store.entry(day) != nil ? .black.opacity(0.5) : .clear, radius: 2)
                }
            }
            .frame(width: side - (blocks ? 1 : 0), height: side - (blocks ? 1 : 0))
            .clipShape(Circle())
            .overlay { if !blocks && calendar.isDateInToday(day) { Circle().stroke(blocks ? .white : .black, lineWidth: 1) } }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .disabled(calendar.startOfDay(for: day) > calendar.startOfDay(for: today))
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(store.entry(day) == nil ? "no sky" : "sky saved")")
    }
    var yearlyCalendar: some View {
        GeometryReader { geometry in
        let circleSize = min(22, max(14, (geometry.size.height - 140) / 27))
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 24).padding(.top, 12)
            HStack {
                Text(month.formatted(.dateTime.year())).font(.system(size: 54, weight: .bold)).tracking(-2)
                Spacer()
                Button { moveYear(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous year")
                Button { moveYear(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next year")
            }.padding(.top, 8)
                YearFlowLayout(spacing: 1) {
                    ForEach(1...12, id: \.self) { number in
                        let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: month), month: number, day: 1))!
                        Text(start.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.system(size: 22, weight: .black)).tracking(-1)
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
                                    } else {
                                        Text("\(index + 1)").font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(.black.opacity(day > today ? 0.25 : 0.7))
                                    }
                                }
                                .frame(width: circleSize, height: circleSize).clipShape(Circle())
                                .overlay { if calendar.isDateInToday(day) { Circle().stroke(.black, lineWidth: 1) } }
                                .frame(width: circleSize, height: circleSize)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(calendar.startOfDay(for: day) > calendar.startOfDay(for: today))
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
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            store.error = "Camera is unavailable on this device. Use Above on an iPhone to record your sky."
            return
        }
        captureDate = date
        camera = true
    }
    func skyGrid(photoSize: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
            ForEach(Array(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"].enumerated()), id: \.offset) { _, label in
                Text(label).font(.system(size: 10, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.bottom, 8)
            }
            ForEach(-offset..<0, id: \.self) { _ in Color.clear.frame(height: photoSize) }
            ForEach(days, id: \.self) { day in
                Button {
                    if let entry = store.entry(day) { selected = entry }
                    else { openCamera(on: day) }
                } label: {
                    VStack(spacing: 0) {
                        ZStack {
                            if let entry = store.entry(day), let image = store.image(entry) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Circle().fill(Color(white: 0.95))
                                if calendar.isDateInToday(day) {
                                    Image(systemName: "plus").font(.system(size: 17, weight: .light))
                                }
                            }
                        }
                        .frame(width: photoSize, height: photoSize).clipShape(Circle())
                        .overlay {
                            if calendar.isDate(day, inSameDayAs: today) {
                                Circle().strokeBorder(.black, lineWidth: 1.5)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .center).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(calendar.startOfDay(for: day) > calendar.startOfDay(for: Date()))
                .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(store.entry(day) == nil ? "no sky" : "sky saved")")
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
                    SkyMediaView(poster: poster, gifURL: mediaURL)
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
        .background(paper).foregroundStyle(.black)
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
                    AboveWordmark(height: 26)
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
                                Circle().stroke(.black.opacity(0.15), lineWidth: 2)
                                Circle().trim(from: 0, to: progress)
                                    .stroke(.black, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
            .background(paper).foregroundStyle(.black)
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
    func positions(width: CGFloat, subviews: Subviews) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
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
        Text("above")
            .font(.system(size: height, weight: .regular))
            .tracking(-height * 2 / 85)
            .accessibilityLabel("above")
    }
}
