import MapKit
import SwiftUI

// MARK: - Rain radar (RainViewer tiles on MapKit)

final class RadarService: ObservableObject {
    static let shared = RadarService()
    struct Frame: Hashable { let time: Date; let path: String; let nowcast: Bool }
    @Published private(set) var host = ""
    @Published private(set) var frames: [Frame] = []
    private var loadedAt = Date.distantPast

    func load() {
        guard Date().timeIntervalSince(loadedAt) > 300 else { return }
        loadedAt = Date()
        Task {
            guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let host = j["host"] as? String, let radar = j["radar"] as? [String: Any] else {
                await MainActor.run { self.loadedAt = .distantPast }
                return
            }
            func frames(_ key: String, nowcast: Bool) -> [Frame] {
                (radar[key] as? [[String: Any]] ?? []).compactMap { f in
                    guard let t = f["time"] as? Double, let p = f["path"] as? String else { return nil }
                    return Frame(time: Date(timeIntervalSince1970: t), path: p, nowcast: nowcast)
                }
            }
            let all = frames("past", nowcast: false) + frames("nowcast", nowcast: true)
            await MainActor.run {
                self.host = host
                self.frames = all
            }
        }
    }
}

final class RadarTileOverlay: MKTileOverlay {
    init(host: String, path: String) {
        super.init(urlTemplate: "\(host)\(path)/256/{z}/{x}/{y}/2/1_1.png")
        canReplaceMapContent = false
        maximumZ = 7
        tileSize = CGSize(width: 256, height: 256)
    }
}

struct RadarMapView: NSViewRepresentable {
    let center: CLLocationCoordinate2D
    let host: String
    let frame: RadarService.Frame?

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.showsCompass = false
        map.showsZoomControls = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 3.2, longitudeDelta: 4.5)), animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = center
        map.addAnnotation(pin)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        guard let frame, !host.isEmpty else { return }
        let c = context.coordinator
        let key = frame.path
        if c.current == key { return }
        c.current = key
        let overlay = c.cache[key] ?? RadarTileOverlay(host: host, path: frame.path)
        c.cache[key] = overlay
        let old = map.overlays
        map.addOverlay(overlay, level: .aboveLabels)
        // Keep the previous frame briefly to avoid flicker.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { map.removeOverlays(old.filter { $0 !== overlay }) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var current: String?
        var cache: [String: MKTileOverlay] = [:]

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: t)
                r.alpha = 0.75
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

struct WeatherHoverList: View {
    let city: String
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var radar = RadarService.shared
    @State private var index = 0
    @State private var playing = true
    private let tick = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = weather.data[city] {
                HStack(spacing: 10) {
                    Image(systemName: WeatherService.symbol(d.code)).symbolRenderingMode(.multicolor).font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(d.temp.rounded()))° · \(WeatherService.label(d.code))").font(.headline)
                        Text("\(d.place) · Wind \(Int(d.wind)) km/h").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)

                if let lat = d.lat, let lon = d.lon {
                    ZStack(alignment: .bottomLeading) {
                        RadarMapView(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                     host: radar.host, frame: radar.frames[safe: index])
                            .frame(height: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        HStack(spacing: 6) {
                            Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                                .buttonStyle(.plain)
                            if let f = radar.frames[safe: index] {
                                Text(f.time.formatted(date: .omitted, time: .shortened) + (f.nowcast ? " · Vorhersage" : ""))
                                    .monospacedDigit()
                            } else {
                                Text("Radar wird geladen …")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(8)
                    }
                    .padding(.horizontal, 12)
                    if !radar.frames.isEmpty {
                        GeometryReader { g in
                            let n = max(radar.frames.count, 1)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.fg.opacity(0.12))
                                Capsule().fill(radar.frames[safe: index]?.nowcast == true ? Color.orange : Color.accentColor)
                                    .frame(width: g.size.width * CGFloat(index + 1) / CGFloat(n))
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 12)
                    }
                }

                if let rain = d.rain15, !rain.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rain.contains { $0 > 0.05 } ? "Regen in den nächsten 2 Stunden" : "Kein Regen in den nächsten 2 Stunden")
                            .font(.caption.weight(.semibold))
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(rain.prefix(8).enumerated()), id: \.offset) { i, mm in
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.blue.opacity(mm > 0 ? 0.85 : 0.2))
                                        .frame(height: max(3, min(36, CGFloat(mm) * 24)))
                                    Text(i % 2 == 0 ? "+\(i * 15)" : "").font(.system(size: 8)).foregroundStyle(Theme.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 50, alignment: .bottom)
                    }
                    .padding(.horizontal, 12)
                }

                HStack(spacing: 0) {
                    ForEach(d.days.prefix(5)) { day in
                        VStack(spacing: 3) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_CH"))))
                                .font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                            Image(systemName: WeatherService.symbol(day.code)).symbolRenderingMode(.multicolor)
                            Text("\(Int(day.max.rounded()))° / \(Int(day.min.rounded()))°").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
            } else {
                Text("Wetter wird geladen …").foregroundStyle(Theme.secondary).padding(.horizontal, 12)
            }
        }
        .onAppear {
            radar.load()
            weather.fetch(city, force: weather.data[city]?.lat == nil)
            index = max(0, (radar.frames.lastIndex { !$0.nowcast } ?? 0))
        }
        .onReceive(tick) { _ in
            guard playing, !radar.frames.isEmpty else { return }
            index = (index + 1) % radar.frames.count
        }
    }
}


// MARK: - Saved weather places

enum WeatherPlaces {
    static func list(_ w: WidgetInstance) -> [String] {
        w.cfg("places").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func add(to w: WidgetInstance) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Ort hinzufügen"
        alert.informativeText = "Zum Beispiel „Bern“, „Konstanz, Deutschland“ oder „New York“."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Ort"
        alert.accessoryView = field
        alert.addButton(withTitle: "Hinzufügen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let place = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return }
        var l = list(w)
        if !l.contains(place) { l.append(place) }
        DockStore.shared.update(w.id) {
            $0.config["places"] = l.joined(separator: "\n")
            $0.config["city"] = place
        }
    }

    static func remove(_ place: String, from w: WidgetInstance) {
        DockStore.shared.update(w.id) {
            $0.config["places"] = list(w).filter { $0 != place }.joined(separator: "\n")
            if $0.config["city"] == place { $0.config["city"] = "auto" }
        }
    }
}
