import SwiftUI
import FantasyCore

struct ScoreText: View {
    let value: Decimal?
    var large = false
    var body: some View {
        Text(value?.exact ?? "—")
            .font(large ? .system(.largeTitle,design:.rounded,weight:.bold) : .system(.title3,design:.rounded,weight:.semibold))
            .monospacedDigit().contentTransition(.numericText())
            .accessibilityLabel(value.map { "\($0.exact) fantasy points" } ?? "Score unavailable")
            .textSelection(.enabled)
    }
}
struct SourceStatus: View {
    let date: Date
    let stale: Bool
    var source = "ESPN unofficial"
    var body: some View {
        VStack(alignment:.leading,spacing:3) {
            Label(stale ? "Cached · may be delayed" : "Last retrieved",systemImage:stale ? "clock.badge.exclamationmark" : "arrow.clockwise")
                .foregroundStyle(stale ? Color.orange : Color.secondary)
            Text("\(source) · \(date.formatted(date:.abbreviated,time:.standard))")
                .foregroundStyle(.secondary)
        }.font(.caption).accessibilityElement(children:.combine)
    }
}
struct TeamScoreColumn: View {
    let name: String
    let summary: ScoreSummary
    var leading = true
    var body: some View {
        VStack(alignment:leading ? .leading : .trailing,spacing:8) {
            Text(name).font(.headline).lineLimit(3)
            ScoreText(value:summary.local ?? summary.official,large:true)
            Text(summary.local != nil ? "Local score" : "ESPN score").font(.caption).foregroundStyle(.secondary)
            if let projected = summary.projected { Text("Projected \(projected.exact)").font(.caption).foregroundStyle(.secondary) }
            Label("\(summary.playing) playing · \(summary.remaining) upcoming",systemImage:"person.fill").font(.caption)
            if let difference = summary.difference, difference != 0 {
                Text("ESPN \(summary.official?.exact ?? "—") · Δ \(difference.exact)").font(.caption).foregroundStyle(.orange)
            }
        }.frame(maxWidth:.infinity,alignment:leading ? .leading : .trailing)
    }
}
struct MatchupCard: View {
    let league: LeagueState
    let model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text(league.snapshot.name).font(.headline)
                    Text("\(league.snapshot.season) · Week \(league.snapshot.week) · \(league.rules.name)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(league.team?.record ?? "—").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let mine = league.team, let opponent = league.opponent {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.top,spacing:16) {
                        TeamScoreColumn(name:mine.name,summary:model.summary(mine,league:league))
                        TeamScoreColumn(name:opponent.name,summary:model.summary(opponent,league:league),leading:false)
                    }
                    VStack(alignment:.leading,spacing:20) {
                        TeamScoreColumn(name:mine.name,summary:model.summary(mine,league:league))
                        TeamScoreColumn(name:opponent.name,summary:model.summary(opponent,league:league))
                    }
                }
            } else { Text("\(league.team?.name ?? "Team unavailable") · Bye or no matchup available").foregroundStyle(.secondary) }
            SourceStatus(date:league.snapshot.fetchedAt,stale:model.stale(league))
            if let error = league.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical,8)
    }
}
struct PlayerAvatar: View {
    let player: RosterPlayer
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let url = player.photoURL, url.scheme == "https" {
                AsyncImage(url:url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName:"person.fill").resizable().scaledToFit().padding(10) }
            } else { Image(systemName:player.position == "D/ST" ? "shield.lefthalf.filled" : "person.fill").resizable().scaledToFit().padding(10) }
        }.frame(width:size,height:size).background(.quaternary,in:Circle()).clipShape(Circle()).accessibilityHidden(true)
    }
}
struct EmptyLeaguesView: View {
    let connect: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Your teams, together",systemImage:"football.fill")
        } description: {
            Text("Connect an ESPN league to see your matchups and every player you own. Public leagues need only an ID and season.")
        } actions: {
            Button("Connect ESPN league",action:connect).buttonStyle(.glassProminent)
        }
    }
}
