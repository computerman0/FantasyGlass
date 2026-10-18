import Foundation

public enum RuleMode: String, Codable, CaseIterable, Sendable { case linear, threshold, range, perWhole }

public struct ScoringRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var stat: String
    public var label: String
    public var multiplier: Decimal
    public var mode: RuleMode
    public var lower: Decimal?
    public var upper: Decimal?
    public var positionMultipliers: [String: Decimal]
    public init(id: String = UUID().uuidString, stat: String, label: String, multiplier: Decimal, mode: RuleMode = .linear, lower: Decimal? = nil, upper: Decimal? = nil, positionMultipliers: [String: Decimal] = [:]) {
        self.id = id; self.stat = stat; self.label = label; self.multiplier = multiplier; self.mode = mode; self.lower = lower; self.upper = upper; self.positionMultipliers = positionMultipliers
    }
}

public struct ScoringConfiguration: Codable, Equatable, Sendable {
    public var name: String
    public var rules: [ScoringRule]
    public var issues: [String]
    public init(name: String, rules: [ScoringRule], issues: [String] = []) { self.name = name; self.rules = rules; self.issues = issues }
    public static func standard(ppr: Decimal = 0) -> ScoringConfiguration {
        let values: [(String, Decimal)] = [("3", Decimal(string:"0.04")!), ("4",4),("20",-2),("24",Decimal(string:"0.1")!), ("25",6),("53",ppr),("42",Decimal(string:"0.1")!),("43",6),("72",-2),("19",2),("26",2),("44",2),("80",3),("77",4),("74",5),("86",1),("88",-1),("99",1),("95",2),("96",2),("98",2),("97",2),("105",6),("89",10),("90",7),("91",4),("92",1),("121",1),("123",-1),("124",-4),("125",-4)]
        return .init(name: ppr == 1 ? "PPR" : ppr == Decimal(string:"0.5")! ? "Half PPR" : "Standard",
                     rules: values.map { ScoringRule(id: $0.0, stat: $0.0, label: StatCatalog.label($0.0), multiplier: $0.1) })
    }
}

public struct ScoringContribution: Identifiable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var raw: Decimal
    public var units: Decimal
    public var rate: Decimal
    public var points: Decimal
    public var mode: RuleMode
}
public struct ScoringResult: Sendable, Equatable {
    public var total: Decimal
    public var contributions: [ScoringContribution]
    public var issues: [String]
}

public enum ScoringEngine {
    /// Sparse ESPN stat maps omit zero-valued categories. A nil entire stat line must be handled by the caller.
    public static func calculate(stats: [String: Decimal], position: String, rules: ScoringConfiguration) -> ScoringResult {
        var items: [ScoringContribution] = [], issues = rules.issues
        var total: Decimal = 0
        for rule in rules.rules {
            let rate = rule.positionMultipliers[position] ?? rule.multiplier
            let raw = stats[rule.stat] ?? 0
            var units = raw
            switch rule.mode {
            case .linear: break
            case .threshold:
                guard let lower = rule.lower else { issues.append("\(rule.label): missing threshold"); continue }
                units = raw >= lower ? 1 : 0
            case .range:
                guard let lower = rule.lower, let upper = rule.upper, lower <= upper else { issues.append("\(rule.label): invalid range"); continue }
                units = (raw >= lower && raw <= upper) ? 1 : 0
            case .perWhole:
                guard let size = rule.lower, size > 0 else { issues.append("\(rule.label): invalid whole-unit size"); continue }
                var dividend = raw, divisor = size, quotient = Decimal(), rounded = Decimal()
                // Directed division prevents a very long fractional quotient from
                // rounding up across an integer boundary before whole-unit truncation.
                let divisionStatus = NSDecimalDivide(&quotient,&dividend,&divisor,raw < 0 ? .up : .down)
                if divisionStatus != .noError && divisionStatus != .lossOfPrecision {
                    issues.append("\(rule.label): division exceeds decimal capacity"); continue
                }
                NSDecimalRound(&rounded, &quotient, 0, raw < 0 ? .up : .down)
                units = rounded
            }
            var mutableUnits = units, mutableRate = rate, points = Decimal()
            let productStatus = NSDecimalMultiply(&points,&mutableUnits,&mutableRate,.plain)
            if productStatus != .noError { issues.append("\(rule.label): decimal capacity exceeded; precision is not guaranteed") }
            if points.isNaN { continue }
            var previousTotal = total
            let sumStatus = NSDecimalAdd(&total,&previousTotal,&points,.plain)
            if sumStatus != .noError { issues.append("Total exceeds decimal capacity; precision is not guaranteed") }
            if raw != 0 || points != 0 { items.append(.init(id: rule.id, label: rule.label, raw: raw, units: units, rate: rate, points: points, mode: rule.mode)) }
        }
        if total.isNaN { issues.append("Total exceeds decimal precision") }
        return ScoringResult(total: total, contributions: items, issues: issues)
    }
}
