import WidgetKit
import SwiftUI

struct SkyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSkySnapshot
}
struct SkyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SkyWidgetEntry { .init(date: Date(), snapshot: .init(photos: [:])) }
    func getSnapshot(in context: Context, completion: @escaping (SkyWidgetEntry) -> Void) {
        completion(.init(date: Date(), snapshot: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SkyWidgetEntry>) -> Void) {
        let now = Date(), calendar = Calendar.current
        let snapshot = WidgetSkySnapshot.load()
        var entries = [SkyWidgetEntry(date: now, snapshot: snapshot)]
        for offset in 1...7 {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) {
                entries.append(.init(date: midnight, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
struct SkyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SkyWidgetEntry
    private func color(_ rgb: [Double]?, fallback: [Double]) -> Color {
        let values = rgb?.count == 3 ? rgb! : fallback
        return Color(red: values[0], green: values[1], blue: values[2])
    }
    private var ink: Color { color(entry.snapshot.inkRGB, fallback: [0, 0, 0]) }
    private var background: Color { color(entry.snapshot.backgroundRGB, fallback: [0.985, 0.98, 0.965]) }
    private var emptyColor: Color {
        let rgb = entry.snapshot.backgroundRGB ?? [0.985, 0.98, 0.965]
        return color(rgb.map { $0 * 0.91 + 0.58 * 0.09 }, fallback: [0.95, 0.95, 0.95])
    }
    private var week: [Date] {
        let calendar = Calendar.current
        let offset = (calendar.component(.weekday, from: entry.date) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: entry.date))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
    var body: some View {
        Group {
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(Array(week.enumerated()), id: \.offset) { index, date in
                            VStack(spacing: 7) {
                                Text(["M", "T", "W", "T", "F", "S", "S"][index])
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.6))
                                GeometryReader { geometry in
                                    day(date).frame(width: geometry.size.width, height: geometry.size.width)
                                }.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }.padding(16)
            } else {
                day(entry.date).padding(15)
            }
        }
        .containerBackground(for: .widget) { background }
    }
    @ViewBuilder private func day(_ date: Date) -> some View {
        let data = entry.snapshot.photos[WidgetSkySnapshot.key(date)]
        let image = data.flatMap(UIImage.init(data:))
        let today = Calendar.current.isDate(date, inSameDayAs: entry.date)
        let circle = ZStack {
            if let image {
                if #available(iOS 18.0, *) {
                    Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            } else {
                if family == .systemSmall {
                    Circle().fill(emptyColor).padding(18)
                    Circle().strokeBorder(Color.gray.opacity(0.6), lineWidth: 1).padding(18)
                    CircularPrompt().foregroundStyle(ink)
                } else {
                    Circle().fill(emptyColor)
                }
                if today && family != .systemSmall {
                    Image(systemName: "plus").font(.system(size: family == .systemSmall ? 32 : 18, weight: .ultraLight))
                        .foregroundStyle(ink)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit).clipShape(Circle())
        .overlay { if today && family != .systemSmall { Circle().strokeBorder(Color.gray.opacity(0.6), lineWidth: 1) } }
        if image != nil || today {
            Link(destination: WidgetSkySnapshot.link(for: date, hasPhoto: image != nil)) { circle }
                .accessibilityLabel(image != nil ? "Open sky for \(date.formatted(date: .complete, time: .omitted))" : "Record today’s sky")
        } else {
            circle.accessibilityLabel("No sky for \(date.formatted(date: .complete, time: .omitted))")
        }
    }
}
struct CircularPrompt: View {
    private let letters = Array("RECORD YOUR SKY · RECORD YOUR SKY · ")
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ForEach(letters.indices, id: \.self) { index in
                    let angle = Double(index) / Double(letters.count) * 360 - 90
                    Text(String(letters[index]))
                        .font(.system(size: side * 0.075, weight: .medium))
                        .rotationEffect(.degrees(angle + 90))
                        .position(x: side / 2 + cos(angle * .pi / 180) * side * 0.455,
                                  y: side / 2 + sin(angle * .pi / 180) * side * 0.455)
                }
            }
        }.accessibilityHidden(true)
    }
}
@main struct AboveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AboveSky", provider: SkyProvider()) { entry in SkyWidgetView(entry: entry) }
            .configurationDisplayName("Your sky")
            .description("Today’s sky, or a little sky for every day of the week.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
            .containerBackgroundRemovable(true)
    }
}
