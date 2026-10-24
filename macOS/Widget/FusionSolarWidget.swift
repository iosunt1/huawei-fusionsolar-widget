import FusionSolarKit
import SwiftUI
import WidgetKit

private struct SolarEntry: TimelineEntry {
    let date: Date
    let snapshot: SolarSnapshot?
    let message: String?
}

private struct SolarProvider: TimelineProvider {
    func placeholder(in context: Context) -> SolarEntry {
        SolarEntry(
            date: .now,
            snapshot: SolarSnapshot(
                stationName: "Solar plant",
                pvPower: 3.25,
                batteryPercent: 72,
                batteryPower: 0.8,
                batteryMode: "charge",
                housePower: 1.1,
                gridPower: 1.35,
                gridMode: "export",
                todayEnergy: 12.5
            ),
            message: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SolarEntry) -> Void) {
        Task {
            completion(await makeEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SolarEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(15 * 60))))
        }
    }

    private func makeEntry() async -> SolarEntry {
        let credentials: FusionSolarCredentials
        do {
            credentials = try SharedConfiguration.load()
        } catch {
            return SolarEntry(date: .now, snapshot: nil, message: error.localizedDescription)
        }
        guard credentials.isConfigured else {
            return SolarEntry(date: .now, snapshot: nil, message: "Open FusionSolar Widget to set up your account.")
        }
        do {
            let data = try await FusionSolarClient(credentials: credentials).fetchSnapshot()
            return SolarEntry(date: .now, snapshot: data, message: nil)
        } catch {
            return SolarEntry(date: .now, snapshot: nil, message: error.localizedDescription)
        }
    }
}

private struct SolarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SolarEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if family == .systemSmall {
                    small(snapshot)
                } else {
                    medium(snapshot)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("FusionSolar", systemImage: "sun.max.fill")
                        .font(.headline)
                    Text(entry.message ?? "No data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding()
    }

    private func small(_ data: SolarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(data.stationName)
            Spacer(minLength: 0)
            Text(data.pvText)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Label("PV now", systemImage: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            metric("Today", value: data.todayText)
            metric("Battery", value: data.batteryPercentText)
        }
    }

    private func medium(_ data: SolarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(data.stationName)
            HStack(alignment: .firstTextBaseline) {
                Text(data.pvText)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                Text("PV now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(data.todayText)
                    .font(.headline)
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                let batteryTitle = data.batteryMode.isEmpty ? "Battery" : "Battery \(data.batteryMode.capitalized)"
                let batteryReading = data.batteryPower == nil
                    ? data.batteryPercentText
                    : "\(data.batteryPercentText) · \(data.batteryText)"
                metric(batteryTitle, value: batteryReading)
                Spacer()
                metric("Home", value: data.houseText)
                Spacer()
                metric(data.gridMode.isEmpty ? "Grid" : "Grid \(data.gridMode.capitalized)", value: data.gridText)
            }
            Spacer(minLength: 0)
            Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func header(_ name: String) -> some View {
        Label(name.isEmpty ? "FusionSolar" : name, systemImage: "sun.max.fill")
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

struct FusionSolarWidget: Widget {
    let kind = "FusionSolarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SolarProvider()) { entry in
            SolarWidgetView(entry: entry)
        }
        .configurationDisplayName("Huawei FusionSolar")
        .description("Live solar production, battery charge, home load and grid flow.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FusionSolarWidgetBundle: WidgetBundle {
    var body: some Widget {
        FusionSolarWidget()
    }
}
