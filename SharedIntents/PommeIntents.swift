import AppIntents
import Foundation

struct CountItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Count My Devices"
    static let description = IntentDescription("Counts how many devices in your Pomme collection match a name.")

    @Parameter(title: "Device", requestValueDialog: "Which device?")
    var device: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = PommeStore.loadSnapshot().items
        let count = PommeMatcher.matches(device, in: items).count
        if count == 0 {
            return .result(dialog: "You don't have any \(device) in your collection.")
        }
        return .result(dialog: "You have \(count) \(device) in your collection.")
    }
}

struct SerialNumberIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Serial Number"
    static let description = IntentDescription("Looks up the serial number of a device in your Pomme collection by name and year.")

    @Parameter(title: "Device", requestValueDialog: "Which device? You can include the year.")
    var device: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let found = PommeMatcher.matches(device, in: PommeStore.loadSnapshot().items)
        guard !found.isEmpty else {
            return .result(dialog: "I couldn't find \(device) in your collection.")
        }
        let withSerial = found.filter { !($0.serial ?? "").isEmpty }
        guard !withSerial.isEmpty else {
            return .result(dialog: "No serial number is recorded for \(device).")
        }
        let answer = withSerial.prefix(3).map { item in
            [item.name, item.year].compactMap { $0 }.joined(separator: " ") + ": " + (item.serial ?? "")
        }.joined(separator: "; ")
        return .result(dialog: "\(answer)")
    }
}

struct PommeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CountItemsIntent(), phrases: [
            "How many devices do I have in \(.applicationName)",
            "Count my devices in \(.applicationName)"
        ], shortTitle: "Count Devices", systemImageName: "number")
        AppShortcut(intent: SerialNumberIntent(), phrases: [
            "Find a serial number in \(.applicationName)",
            "Serial number lookup in \(.applicationName)"
        ], shortTitle: "Serial Number", systemImageName: "barcode")
    }
}
