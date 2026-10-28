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
enum SkyWidgetTheme { case classic, poster }

struct SkyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SkyWidgetEntry
    var theme: SkyWidgetTheme = .classic
    var twoWeeks = false
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
            if theme == .poster {
                poster
            } else if family == .systemMedium {
                classicWeeks
            } else {
                day(entry.date).padding(14)
            }
        }
        .foregroundStyle(ink)
        .containerBackground(for: .widget) { background }
    }
    private var classicWeeks: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let side = max(0, min((geometry.size.width - 16 - gap * 6) / 7,
                                 twoWeeks ? (geometry.size.height - 48) / 2 : geometry.size.height - 70))
            VStack(spacing: twoWeeks ? 9 : 14) {
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(["M", "T", "W", "T", "F", "S", "S"][index])
                            .font(.system(size: twoWeeks ? 11 : 15, weight: .medium))
                            .foregroundStyle(ink.opacity(twoWeeks ? 0.65 : 0.9))
                            .frame(width: side)
                    }
                }
                if twoWeeks {
                    HStack(spacing: gap) {
                        ForEach(week, id: \.self) { date in
                            if let previous = Calendar.current.date(byAdding: .day, value: -7, to: date) {
                                day(previous).frame(width: side, height: side)
                            }
                        }
                    }
                }
                HStack(spacing: gap) {
                    ForEach(week, id: \.self) { date in
                        day(date).frame(width: side, height: side)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private var poster: some View {
        GeometryReader { geometry in
            let side = max(0, min(geometry.size.height - 20, geometry.size.width * 0.46))
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: 14, weight: .bold)).tracking(-0.3)
                        .padding(.bottom, -7)
                    Text(entry.date.formatted(.dateTime.day()))
                        .font(.system(size: 88, weight: .bold))
                        .tracking(-5).minimumScaleFactor(0.7).lineLimit(1)
                    Text(entry.date.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 11, weight: .medium)).tracking(1)
                        .padding(.top, -8)
                }
                Spacer(minLength: 0)
                day(entry.date).frame(width: side, height: side)
            }
            .padding(.leading, 20).padding(.trailing, 10)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .widgetURL(WidgetSkySnapshot.link(for: entry.date,
            hasPhoto: entry.snapshot.photos[WidgetSkySnapshot.key(entry.date)] != nil))
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
                Circle().fill(emptyColor)
                if today {
                    if family == .systemSmall {
                        Image(systemName: "plus")
                            .font(.system(size: 30, weight: .ultraLight))
                            .overlay(alignment: .top) {
                                Text("Record your sky")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(ink.opacity(0.55))
                                    .fixedSize()
                                    .offset(y: 38)
                            }
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: theme == .poster ? 58 : 18, weight: .ultraLight))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit).clipShape(Circle())
        .overlay { if today && (family != .systemSmall || image == nil) {
            Circle().strokeBorder(ink, lineWidth: 1)
        } }
        if image != nil || today {
            Link(destination: WidgetSkySnapshot.link(for: date, hasPhoto: image != nil)) { circle }
                .accessibilityLabel(image != nil ? "Open sky for \(date.formatted(date: .complete, time: .omitted))" : "Record today’s sky")
        } else {
            circle.accessibilityLabel("No sky for \(date.formatted(date: .complete, time: .omitted))")
        }
    }
}
struct AboveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AboveSky", provider: SkyProvider()) { entry in SkyWidgetView(entry: entry) }
            .configurationDisplayName("Classic · 1 week")
            .description("Today’s sky, or a little sky for every day of the week.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
            .containerBackgroundRemovable(true)
    }
}

struct AbovePosterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AbovePoster", provider: SkyProvider()) { entry in
            SkyWidgetView(entry: entry, theme: .poster)
        }
        .configurationDisplayName("Poster")
        .description("A bold date, in your journal’s palette.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}
struct AboveTwoWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AboveTwoWeeks", provider: SkyProvider()) { entry in
            SkyWidgetView(entry: entry, twoWeeks: true)
        }
        .configurationDisplayName("Classic · 2 weeks")
        .description("Last week and this week, one sky at a time.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}
@main struct AboveWidgetBundle: WidgetBundle {
    var body: some Widget {
        AboveWidget()
        AboveTwoWeekWidget()
        AbovePosterWidget()
    }
}
