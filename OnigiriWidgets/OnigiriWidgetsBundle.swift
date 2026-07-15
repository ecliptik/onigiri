import WidgetKit
import SwiftUI

@main
struct OnigiriWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayCardWidget()
        GaugeWidget()
        WaterWidget()
        StreakWidget()
        MonthStatsWidget()
        LogWaterControl()
    }
}
