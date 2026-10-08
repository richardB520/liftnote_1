import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LiftNoteWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

/// 锁屏和灵动岛上的组间休息倒计时
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(state: context.state, title: context.attributes.workoutTitle)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("休息", systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(Color.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                        .font(.title2.bold())
                        .frame(width: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName).font(.subheadline.bold())
                        if !context.state.detail.isEmpty {
                            Text(context.state.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Color.green)
            } compactTrailing: {
                countdown(context.state)
                    .frame(width: 46)
                    .foregroundStyle(Color.green)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Color.green)
            }
        }
    }
}

private func countdown(_ state: RestActivityAttributes.ContentState) -> some View {
    let start = min(state.startedAt, state.endsAt)
    return Text(timerInterval: start...state.endsAt, countsDown: true)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
}

struct RestLockScreenView: View {
    let state: RestActivityAttributes.ContentState
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("组间休息", systemImage: "timer")
                    .font(.caption.bold())
                    .foregroundStyle(Color.green)
                Text(state.exerciseName)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(state.detail.isEmpty ? title : "\(state.detail) · \(title)")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            countdown(state)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(16)
    }
}
