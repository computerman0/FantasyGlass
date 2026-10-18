import Foundation

enum RuntimeEnvironment {
    // LiveContainer publishes these environment markers before loading a guest.
    // This only disables unsupported services; it uses no private Apple API.
    static let isLiveContainer = ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil
        || ProcessInfo.processInfo.environment["LP_HOME_PATH"] != nil

    static let containerLimitations = "LiveContainer mode: foreground league tracking only. Notifications and background refresh require FantasyGlass to be installed as its own signed app."
}
