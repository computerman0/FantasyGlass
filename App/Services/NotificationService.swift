import Foundation
import UserNotifications
import UIKit
import FantasyCore

@MainActor final class NotificationService {
    func requestAuthorization(remote: Bool) async throws -> Bool {
        guard !RuntimeEnvironment.isLiveContainer else { throw ProviderError.invalidInput(RuntimeEnvironment.containerLimitations) }
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])
        if granted && remote { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }
    func deliver(_ alerts: [FantasyAlert], connectionID: String, matchupID: String?) async throws -> Set<String> {
        guard !RuntimeEnvironment.isLiveContainer else { return [] }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return [] }
        var delivered: Set<String> = []
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title; content.body = alert.body; content.sound = .default
            content.threadIdentifier = connectionID
            if let url = MatchupLink.url(connectionID:connectionID,matchupID:matchupID ?? "") { content.userInfo = ["url":url.absoluteString] }
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:alert.id,content:content,trigger:nil))
            delivered.insert(alert.id)
        }
        return delivered
    }
}

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !RuntimeEnvironment.isLiveContainer { UNUserNotificationCenter.current().delegate = self }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        do {
            try KeychainStore().write(deviceToken.map { String(format:"%02x",$0) }.joined(),account:"apns.deviceToken")
            NotificationCenter.default.post(name:.remoteTokenChanged,object:nil)
        } catch { NotificationCenter.default.post(name:.remoteRegistrationFailed,object:error.localizedDescription) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        NotificationCenter.default.post(name:.remoteRegistrationFailed,object:error.localizedDescription)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner,.sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let string = response.notification.request.content.userInfo["url"] as? String
        guard let string, let url = URL(string:string), url.scheme == "fantasyglass" else { return }
        await MainActor.run { UIApplication.shared.open(url,options:[:],completionHandler:nil) }
    }
}
extension Notification.Name {
    static let remoteTokenChanged = Notification.Name("FantasyGlass.remoteTokenChanged")
    static let remoteRegistrationFailed = Notification.Name("FantasyGlass.remoteRegistrationFailed")
}
