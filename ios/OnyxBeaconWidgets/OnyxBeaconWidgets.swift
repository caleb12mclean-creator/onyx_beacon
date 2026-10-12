import WidgetKit
import SwiftUI

// MARK: - Data Model from Flutter home_widget
struct OnyxBeaconEntry: TimelineEntry {
    let date: Date
    let habitsDue: Int
    let tasksPending: Int
    let netToday: String
    let lastUpdated: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> OnyxBeaconEntry {
        OnyxBeaconEntry(date: Date(), habitsDue: 3, tasksPending: 5, netToday: "42.50", lastUpdated: "12:00")
    }
    
    func getSnapshot(in context: Context, completion: @escaping (OnyxBeaconEntry) -> ()) {
        let entry = loadEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<OnyxBeaconEntry>) -> ()) {
        let entry = loadEntry()
        // Refresh every 15 min
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadEntry() -> OnyxBeaconEntry {
        let userDefaults = UserDefaults(suiteName: "group.onyxbeacon")
        let habitsDue = userDefaults?.integer(forKey: "habits_due") ?? 0
        let tasksPending = userDefaults?.integer(forKey: "tasks_pending") ?? 0
        let netToday = userDefaults?.string(forKey: "net_today") ?? "0.00"
        let lastUpdated = userDefaults?.string(forKey: "last_updated") ?? "--:--"
        return OnyxBeaconEntry(date: Date(), habitsDue: habitsDue, tasksPending: tasksPending, netToday: netToday, lastUpdated: lastUpdated)
    }
}

// MARK: - Widget Views
struct OnyxBeaconWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

struct SmallWidgetView: View {
    let entry: OnyxBeaconEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text("Onyx Beacon")
                    .font(.caption2).bold()
                Spacer()
            }
            Spacer()
            Text("\(entry.habitsDue)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
            Text("Habits Due")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text("Updated \(entry.lastUpdated)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

struct MediumWidgetView: View {
    let entry: OnyxBeaconEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "command.circle.fill")
                    .foregroundColor(Color(red: 0.29, green: 0.31, blue: 0.41))
                Text("Onyx Beacon — Command Center")
                    .font(.caption).bold()
                Spacer()
                Text(entry.lastUpdated)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    HStack { Image(systemName: "bolt.fill").foregroundColor(.orange); Text("\(entry.habitsDue)").bold() }
                    Text("Habits Due").font(.caption2).foregroundColor(.secondary)
                }
                Divider()
                VStack(alignment: .leading) {
                    HStack { Image(systemName: "checklist").foregroundColor(.blue); Text("\(entry.tasksPending)").bold() }
                    Text("Tasks").font(.caption2).foregroundColor(.secondary)
                }
                Divider()
                VStack(alignment: .leading) {
                    HStack { Image(systemName: "dollarsign.circle.fill").foregroundColor(.green); Text("$\(entry.netToday)").bold() }
                    Text("Net Today").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("Welcome back, Caleb.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

struct LargeWidgetView: View {
    let entry: OnyxBeaconEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "command.circle.fill")
                    .foregroundColor(Color(red: 0.29, green: 0.31, blue: 0.41))
                Text("Onyx Beacon — Command Center")
                    .font(.headline)
                Spacer()
            }
            Text("Welcome back, Caleb. — Daily Briefing")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 20) {
                StatCard(icon: "bolt.fill", color: .orange, value: "\(entry.habitsDue)", label: "Habits Due")
                StatCard(icon: "checklist", color: .blue, value: "\(entry.tasksPending)", label: "Tasks Pending")
                StatCard(icon: "dollarsign.circle.fill", color: .green, value: "$\(entry.netToday)", label: "Net Today")
            }
            Spacer()
            HStack {
                Text("Last updated: \(entry.lastUpdated)")
                Spacer()
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundColor(.secondary)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

struct StatCard: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    var body: some View {
        VStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(value)
                .font(.title2).bold()
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - Widget Definition
struct OnyxBeaconWidgets: Widget {
    let kind: String = "OnyxBeaconWidgets"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OnyxBeaconWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Onyx Beacon")
        .description("Your Life Command Center — habits, tasks, net today. Welcome back, Caleb.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    OnyxBeaconWidgets()
} timeline: {
    OnyxBeaconEntry(date: .now, habitsDue: 3, tasksPending: 5, netToday: "125.50", lastUpdated: "14:32")
    OnyxBeaconEntry(date: .now, habitsDue: 1, tasksPending: 2, netToday: "-20.00", lastUpdated: "15:00")
}
