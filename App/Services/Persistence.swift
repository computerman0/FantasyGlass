import Foundation
import SwiftData
import FantasyCore

@Model final class CachedLeague {
    @Attribute(.unique) var id: String
    var connectionData: Data
    var snapshotData: Data
    var overrideData: Data?
    var errorMessage: String?
    var eventData: Data?
    var deliveredData: Data
    init(id: String, connectionData: Data, snapshotData: Data, overrideData: Data? = nil, errorMessage: String? = nil, eventData: Data? = nil, deliveredData: Data = Data("[]".utf8)) {
        self.id = id; self.connectionData = connectionData; self.snapshotData = snapshotData; self.overrideData = overrideData; self.errorMessage = errorMessage; self.eventData = eventData; self.deliveredData = deliveredData
    }
}
@Model final class CachedObject {
    @Attribute(.unique) var id: String
    var data: Data
    init(id: String, data: Data) { self.id = id; self.data = data }
}

struct LeagueState: Identifiable {
    var connection: LeagueConnection
    var snapshot: LeagueSnapshot
    var localOverride: ScoringConfiguration?
    var error: String?
    var event: EventFrame?
    var delivered: Set<String> = []
    var id: String { connection.id }
    var rules: ScoringConfiguration { localOverride ?? snapshot.importedRules }
    var team: FantasyTeam? { snapshot.team(connection.teamID) }
    var matchup: FantasyMatchup? { snapshot.matchup(for: connection.teamID) }
    var opponent: FantasyTeam? {
        let id = matchup?.homeID == connection.teamID ? matchup?.awayID : matchup?.homeID
        return id.flatMap(snapshot.team)
    }
}

@MainActor final class LeagueRepository {
    let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    init(context: ModelContext) { self.context = context }
    func load() throws -> [LeagueState] {
        try context.fetch(FetchDescriptor<CachedLeague>()).map { item in
            LeagueState(connection: try decoder.decode(LeagueConnection.self, from:item.connectionData),
                snapshot: try decoder.decode(LeagueSnapshot.self, from:item.snapshotData),
                localOverride: try item.overrideData.map { try decoder.decode(ScoringConfiguration.self, from:$0) }, error:item.errorMessage,
                event: try item.eventData.map { try decoder.decode(EventFrame.self, from:$0) }, delivered:try decoder.decode(Set<String>.self, from:item.deliveredData))
        }.sorted { $0.snapshot.name.localizedCaseInsensitiveCompare($1.snapshot.name) == .orderedAscending }
    }
    func save(_ state: LeagueState) throws {
        let id = state.id
        let query = FetchDescriptor<CachedLeague>(predicate:#Predicate { $0.id == id })
        let record = try context.fetch(query).first ?? CachedLeague(id:id,connectionData:Data(),snapshotData:Data())
        if record.modelContext == nil { context.insert(record) }
        record.connectionData = try encoder.encode(state.connection)
        record.snapshotData = try encoder.encode(state.snapshot)
        record.overrideData = try state.localOverride.map(encoder.encode)
        record.errorMessage = state.error
        record.eventData = try state.event.map(encoder.encode)
        record.deliveredData = try encoder.encode(state.delivered)
        try context.save()
    }
    func remove(_ id: String) throws {
        let query = FetchDescriptor<CachedLeague>(predicate:#Predicate { $0.id == id })
        for record in try context.fetch(query) { context.delete(record) }
        try context.save()
    }
    func store<T: Encodable>(_ value: T, key: String) throws {
        let query = FetchDescriptor<CachedObject>(predicate:#Predicate { $0.id == key })
        let object = try context.fetch(query).first ?? CachedObject(id:key,data:Data())
        if object.modelContext == nil { context.insert(object) }
        object.data = try encoder.encode(value)
        try context.save()
    }
    func read<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        let query = FetchDescriptor<CachedObject>(predicate:#Predicate { $0.id == key })
        return try context.fetch(query).first.map { try decoder.decode(type,from:$0.data) }
    }
}
