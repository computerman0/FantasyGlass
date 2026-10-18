import SwiftUI
import WidgetKit
import ActivityKit

@main struct FantasyGlassWidgetBundle: WidgetBundle {
    var body: some Widget { MatchupLiveActivity() }
}

struct MatchupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:MatchupActivityAttributes.self) { context in
            LockScreenMatchupView(context:context)
                .widgetURL(MatchupLink.url(connectionID:context.attributes.connectionID,matchupID:context.attributes.matchupID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandTeam(name:context.attributes.myTeam,score:context.state.myScore,projection:context.state.myProjection,remaining:context.state.myRemaining,leading:true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTeam(name:context.attributes.opponentTeam,score:context.state.opponentScore,projection:context.state.opponentProjection,remaining:context.state.opponentRemaining,leading:false)
                }
                DynamicIslandExpandedRegion(.center) { Image(systemName:"football.fill").foregroundStyle(.cyan).accessibilityHidden(true) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing:6) {
                        Text(context.state.status).font(.caption).lineLimit(2)
                        HStack {
                            Text(context.isStale ? "Delayed" : context.state.scoreSource).foregroundStyle(context.isStale ? Color.orange : Color.secondary)
                            Spacer()
                            Text(Date(timeIntervalSince1970:context.state.updatedAt),style:.time)
                        }.font(.caption2)
                    }.padding(.top,6)
                }
            } compactLeading: {
                HStack(spacing:3) {
                    Image(systemName:context.isStale ? "clock" : context.state.leader > 0 ? "arrowtriangle.up.fill" : "football.fill")
                        .font(.system(size:8)).foregroundStyle(context.isStale ? .orange : .cyan)
                    Text(context.state.myScore).monospacedDigit().minimumScaleFactor(0.6)
                }.accessibilityLabel("\(context.attributes.myTeam), \(context.state.myScore) points\(context.isStale ? ", delayed" : "")")
            } compactTrailing: {
                HStack(spacing:3) {
                    Text(context.state.opponentScore).monospacedDigit().minimumScaleFactor(0.6)
                    if context.state.leader < 0 { Image(systemName:"arrowtriangle.up.fill").font(.system(size:8)).foregroundStyle(.orange) }
                }.accessibilityLabel("\(context.attributes.opponentTeam), \(context.state.opponentScore) points")
            } minimal: {
                Image(systemName:context.isStale ? "clock.badge.exclamationmark" : "football.fill")
                    .foregroundStyle(context.isStale ? .orange : context.state.leader < 0 ? .orange : .cyan)
                    .accessibilityLabel(context.isStale ? "Fantasy scores delayed" : context.state.leader > 0 ? "Your team is leading" : context.state.leader < 0 ? "Your team is trailing" : "Fantasy matchup tied")
            }
            .keylineTint(.cyan)
            .widgetURL(MatchupLink.url(connectionID:context.attributes.connectionID,matchupID:context.attributes.matchupID))
        }
    }
}

private struct IslandTeam: View {
    let name: String
    let score: String
    let projection: String?
    let remaining: Int
    let leading: Bool
    var body: some View {
        VStack(alignment:leading ? .leading : .trailing,spacing:4) {
            Text(name).font(.caption.weight(.semibold)).lineLimit(2)
            Text(score).font(.system(.title2,design:.rounded,weight:.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            if let projection { Text("Proj \(projection)").font(.caption2).lineLimit(1).minimumScaleFactor(0.6) }
            Text("\(remaining) upcoming").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children:.combine)
    }
}

struct LockScreenMatchupView: View {
    let context: ActivityViewContext<MatchupActivityAttributes>
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label(context.attributes.leagueName,systemImage:"football.fill").font(.caption.weight(.semibold))
                Spacer()
                if context.isStale { Label("Delayed",systemImage:"clock").font(.caption).foregroundStyle(.orange) }
            }
            HStack(alignment:.top,spacing:16) {
                IslandTeam(name:context.attributes.myTeam,score:context.state.myScore,projection:context.state.myProjection,remaining:context.state.myRemaining,leading:true)
                Spacer(minLength:0)
                IslandTeam(name:context.attributes.opponentTeam,score:context.state.opponentScore,projection:context.state.opponentProjection,remaining:context.state.opponentRemaining,leading:false)
            }
            ProgressView(value:context.state.progress).tint(.cyan).accessibilityLabel("Starter games completed").accessibilityValue("\(Int(context.state.progress*100)) percent")
            HStack {
                Text("\(context.state.myPlaying) playing · \(context.state.opponentPlaying) opponent playing")
                Spacer()
                Text(Date(timeIntervalSince1970:context.state.updatedAt),style:.time)
            }.font(.caption2).foregroundStyle(.secondary)
            Text(context.state.status).font(.caption2).lineLimit(2)
        }.padding(16)
    }
}

#Preview("Matchup · Lock Screen",as:.content,using:MatchupActivityAttributes(connectionID:"preview",matchupID:"7",myTeam:"Glass Cannons",opponentTeam:"Sunday Club",leagueName:"Preview League")) {
    MatchupLiveActivity()
} contentStates: {
    MatchupActivityAttributes.ContentState(myScore:"103.72",opponentScore:"97.5",myProjection:"124.8",opponentProjection:"118.2",myRemaining:2,opponentRemaining:3,myPlaying:4,opponentPlaying:3,progress:0.45,leader:1,status:"BUF @ KC · Q3 08:42",updatedAt:Date.now.timeIntervalSince1970,scoreSource:"Preview only")
}
