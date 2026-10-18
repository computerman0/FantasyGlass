import Foundation
import Testing
@testable import FantasyCore

@Test func alertTransitionsAndFirstRefresh() {
    let preferences = AlertPreferences(enabled:Set(AlertKind.allCases),thresholds:["1":20])
    let before = EventFrame(scope:"league:7",players:["1":.init(name:"Player",touchdowns:0,points:15,injury:"ACTIVE")],games:["g":.live],ownScore:80,opponentScore:81,lastGameLive:false,finished:false)
    var after = before
    after.players["1"] = .init(name:"Player",touchdowns:1,points:21,injury:"OUT")
    after.games["g"] = .halftime; after.ownScore = 86; after.lastGameLive = true
    #expect(EventDetector.detect(previous:nil,current:after,preferences:preferences).isEmpty)
    let alerts = EventDetector.detect(previous:before,current:after,preferences:preferences)
    #expect(Set(alerts.map(\.kind)) == [.touchdown,.threshold,.injuredOut,.halftime,.leadChange,.closeFinalGame])
    #expect(EventDetector.detect(previous:after,current:after,preferences:preferences).isEmpty)
    var corrected = after; corrected.finished = true; corrected.ownScore = 79
    after.finished = true
    #expect(EventDetector.detect(previous:after,current:corrected,preferences:preferences).contains { $0.kind == .correction })
    corrected.scope = "league:8"
    #expect(EventDetector.detect(previous:after,current:corrected,preferences:preferences).isEmpty)
}
