#if DEBUG
import SwiftUI
import SwiftData
import FantasyCore

@MainActor enum PreviewSupport {
    static func model() -> AppModel {
        let container = try! ModelContainer(for:CachedLeague.self,CachedObject.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let model = AppModel(container:container)
        model.preferences.onboardingComplete = true
        let rules = ScoringConfiguration.standard(ppr:1)
        let allen = RosterPlayer(id:"3918298",name:"Josh Allen",nflTeam:"BUF",position:"QB",scoringPosition:"0",slot:0,jersey:"17",
            weeks:[.init(week:7,stats:["3":275,"4":3,"24":45],projectionStats:["3":300,"4":3,"24":50],official:Decimal(string:"27.5"))],source:"Preview fixture")
        let opponent = RosterPlayer(id:"3139477",name:"Patrick Mahomes",nflTeam:"KC",position:"QB",scoringPosition:"0",slot:0,
            weeks:[.init(week:7,stats:["3":240,"4":2,"24":30],projectionStats:["3":300,"4":3,"24":40],official:Decimal(string:"20.6"))],source:"Preview fixture")
        let teams = [FantasyTeam(id:1,name:"Glass Cannons",wins:4,losses:2,roster:[allen]),FantasyTeam(id:2,name:"Sunday Club",wins:3,losses:3,roster:[opponent])]
        let snapshot = LeagueSnapshot(leagueID:"preview",season:2026,name:"Preview · Sunday League",week:7,matchupPeriod:7,teams:teams,
            schedule:[.init(id:"7",period:7,homeID:1,awayID:2,homeOfficial:Decimal(string:"27.5"),awayOfficial:Decimal(string:"20.6"),weeks:[7])],importedRules:rules)
        model.leagues = [.init(connection:.init(leagueID:"preview",season:2026,teamID:1),snapshot:snapshot)]
        model.gamesByWeek["2026:7"] = [.init(id:"preview-game",home:"KC",away:"BUF",start:.now,phase:.live,detail:"Q3 08:42",period:3,clock:"08:42")]
        return model
    }
}
#Preview("Dashboard · sample data") { DashboardView(model:PreviewSupport.model()) }
#Preview("Player · sample data") { NavigationStack { PlayerDetailView(model:PreviewSupport.model(),playerID:"3918298") } }

#endif
