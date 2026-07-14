import WidgetKit
import SwiftUI

@main
struct OnigiriWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayCardWidget()
        MeterWidget()
        GaugeWidget()
        ProgressWidget()
        WaterWidget()
        StreakWidget()
        MonthWidget()
        TrendWidget()
        LogWaterControl()
    }
}
