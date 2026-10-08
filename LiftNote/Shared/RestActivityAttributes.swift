import ActivityKit
import Foundation

/// App 和锁屏小组件共用的休息倒计时数据。
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var detail: String
        var startedAt: Date
        var endsAt: Date
    }

    var workoutTitle: String
}
