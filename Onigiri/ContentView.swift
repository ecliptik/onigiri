import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "gauge.with.needle") {
                TodayView()
            }
            Tab("Foods", systemImage: "fork.knife") {
                PlaceholderView(
                    title: "Foods",
                    systemImage: "fork.knife",
                    detail: "Your saved foods and one-tap meals will live here."
                )
            }
            Tab("Water", systemImage: "drop.fill") {
                PlaceholderView(
                    title: "Water",
                    systemImage: "drop.fill",
                    detail: "Quick-add servings toward your daily water goal."
                )
            }
            Tab("Goal", systemImage: "chart.line.downtrend.xyaxis") {
                PlaceholderView(
                    title: "Goal",
                    systemImage: "chart.line.downtrend.xyaxis",
                    detail: "Target weight, daily budget, and your weight trend."
                )
            }
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
                .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
}
