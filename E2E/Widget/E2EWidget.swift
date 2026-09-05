import ActivityKit
import SwiftUI
import WidgetKit

@main
struct E2EWidgetBundle: WidgetBundle {
    var body: some Widget {
        E2ELiveActivity()
    }
}

struct E2ELiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: E2EAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.attributes.name)
                Text("\(context.state.status) · step \(context.state.step)")
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.status) · \(context.state.step)")
                }
            } compactLeading: {
                Text(context.attributes.name)
            } compactTrailing: {
                Text("\(context.state.step)")
            } minimal: {
                Text("\(context.state.step)")
            }
        }
    }
}
