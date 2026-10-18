import SwiftUI
import UserNotifications

#if canImport(UIKit) && !os(watchOS)
import UIKit
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            LaunchDropManager.shared.rescheduleAllActiveDrops()
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        let identifier = response.notification.request.identifier
        if category == BatteryMaintenanceManager.notificationCategory ||
           identifier.hasPrefix("battery_daily_") ||
           identifier.hasPrefix("battery_quarterly_") {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openBatteryMaintenance, object: nil)
            }
        }
    }
}
#elseif os(macOS)
import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            LaunchDropManager.shared.rescheduleAllActiveDrops()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        let identifier = response.notification.request.identifier
        if category == BatteryMaintenanceManager.notificationCategory ||
           identifier.hasPrefix("battery_daily_") ||
           identifier.hasPrefix("battery_quarterly_") {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openBatteryMaintenance, object: nil)
            }
        }
    }
}
#endif

extension Notification.Name {
    static let openBatteryMaintenance = Notification.Name("openBatteryMaintenance")
}

@main struct MyApp: App {
    #if canImport(UIKit) && !os(watchOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @AppStorage("appAppearanceMode") private var appearanceMode: String = AppAppearanceMode.auto.rawValue

    private var preferredScheme: ColorScheme? {
        AppAppearanceMode(rawValue: appearanceMode)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(preferredScheme)
        }
        #if os(visionOS)
        .defaultSize(width: 860, height: 400)
        #endif
        #if os(visionOS)
        ImmersiveSpace(id: "SpatialMuseumImmersiveSpace") {
            SpatialMuseumImmersiveView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }
}
