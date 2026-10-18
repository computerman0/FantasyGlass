import XCTest
import SwiftData
import FantasyCore
@testable import FantasyGlass

@MainActor final class PersistenceTests: XCTestCase {
    func testSnapshotAndOverridesSurviveNewRepository() throws {
        let container = try ModelContainer(for:CachedLeague.self,CachedObject.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let repository = LeagueRepository(context:container.mainContext)
        let imported = ScoringConfiguration.standard()
        let snapshot = LeagueSnapshot(leagueID:"123",season:2026,name:"Cache test",week:7,matchupPeriod:7,teams:[],schedule:[],importedRules:imported,fetchedAt:Date(timeIntervalSince1970:1))
        var state = LeagueState(connection:.init(leagueID:"123",season:2026,teamID:1),snapshot:snapshot,localOverride:.standard(ppr:1))
        try repository.save(state)
        state.error = "Authentication expired"
        try repository.save(state)
        let restored = try XCTUnwrap(LeagueRepository(context:ModelContext(container)).load().first)
        XCTAssertEqual(restored.snapshot,snapshot)
        XCTAssertEqual(restored.snapshot.importedRules,imported)
        XCTAssertEqual(restored.localOverride?.name,"PPR")
        XCTAssertEqual(restored.error,"Authentication expired")
        XCTAssertEqual(restored.snapshot.fetchedAt,Date(timeIntervalSince1970:1))
    }
    func testMultipleOwnedTeamsRemainIndependent() throws {
        let container = try ModelContainer(for:CachedLeague.self,CachedObject.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let repository = LeagueRepository(context:container.mainContext)
        let snapshot = LeagueSnapshot(leagueID:"123",season:2026,name:"Two teams",week:7,matchupPeriod:7,teams:[],schedule:[],importedRules:.standard())
        for id in [1,2] { try repository.save(.init(connection:.init(leagueID:"123",season:2026,teamID:id),snapshot:snapshot)) }
        XCTAssertEqual(try repository.load().count,2)
        try repository.remove("espn:2026:123:1")
        XCTAssertEqual(try repository.load().map(\.connection.teamID),[2])
    }
    func testExactMatchupDeepLinkRoundTrips() throws {
        let url = try XCTUnwrap(MatchupLink.url(connectionID:"espn:2026:123:1",matchupID:"37"))
        XCTAssertEqual(MatchupLink.parse(url)?.connection,"espn:2026:123:1")
        XCTAssertEqual(MatchupLink.parse(url)?.matchup,"37")
        XCTAssertNil(MatchupLink.parse(URL(string:"https://example.com")!))
    }
}
