import WidgetKit
import SwiftUI

@main
struct OnigiriWidgetsBundle: WidgetBundle {
    var body: some Widget {
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
