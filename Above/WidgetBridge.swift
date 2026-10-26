import Foundation
import UIKit
import WidgetKit

struct WidgetSkySnapshot: Codable {
    var photos: [String: Data]
    var backgroundRGB: [Double]? = nil
    var inkRGB: [Double]? = nil
    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.above.skyjournal")?
            .appendingPathComponent("widget-skies.json")
    }
    static func load() -> Self {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return Self(photos: [:]) }
        return snapshot
    }
    @MainActor static func publish(_ images: [(Date, UIImage)], background: UIColor, ink: UIColor) {
        guard let url else { return }
        var photos: [String: Data] = [:]
        for (date, image) in images {
            let thumb = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { _ in
                let scale = max(240 / image.size.width, 240 / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (240 - size.width) / 2, y: (240 - size.height) / 2, width: size.width, height: size.height))
            }
            photos[key(date)] = thumb.jpegData(compressionQuality: 0.8)
        }
        do {
            func components(_ color: UIColor) -> [Double] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                return [Double(r), Double(g), Double(b)]
            }
            try JSONEncoder().encode(Self(photos: photos, backgroundRGB: components(background), inkRGB: components(ink))).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            WidgetCenter.shared.reloadTimelines(ofKind: "AboveSky")
        } catch { /* The journal remains saved even if widget sharing is unavailable. */ }
    }
    static func link(for date: Date, hasPhoto: Bool) -> URL {
        var components = URLComponents()
        components.scheme = "above"
        components.host = hasPhoto ? "entry" : "capture"
        components.queryItems = [URLQueryItem(name: "date", value: key(date))]
        return components.url!
    }
}
