import Foundation
import Testing
@testable import DebrisKit

struct AppMatcherTests {
    let word = InstalledApp(bundleID: "com.microsoft.Word", name: "Microsoft Word", url: URL(fileURLWithPath: "/Applications/Microsoft Word.app"),
                            teamID: "UBF8T346G9", appGroups: ["UBF8T346G9.Office", "UBF8T346G9.OfficeWordWidget"], source: .applications)
    let excel = InstalledApp(bundleID: "com.microsoft.Excel", name: "Microsoft Excel", url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app"),
                             teamID: "UBF8T346G9", appGroups: ["UBF8T346G9.Office"], source: .applications)
    let mau = InstalledApp(bundleID: "com.microsoft.autoupdate2", name: "Microsoft AutoUpdate", url: URL(fileURLWithPath: "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"), source: .other)
    let wordHelper = InstalledApp(bundleID: "com.microsoft.Word.widgetextension", name: "WordWidget", url: URL(fileURLWithPath: "/Applications/Microsoft Word.app/Contents/PlugIns/Widget.appex"), source: .embedded)
    let wordPaywall = InstalledApp(bundleID: "com.microsoft.office.paywall.paywallresources", name: "Paywall", url: URL(fileURLWithPath: "/Applications/Microsoft Word.app/Contents/Frameworks/Paywall.framework"), source: .embedded)
    let wordErrors = InstalledApp(bundleID: "com.microsoft.errorreporting", name: "Microsoft Error Reporting", url: URL(fileURLWithPath: "/Applications/Microsoft Word.app/Contents/SharedSupport/Microsoft Error Reporting.app"), source: .embedded)
    let excelErrors = InstalledApp(bundleID: "com.microsoft.errorreporting", name: "Microsoft Error Reporting", url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app/Contents/SharedSupport/Microsoft Error Reporting.app"), source: .embedded)
    let chrome = InstalledApp(bundleID: "com.google.Chrome", name: "Google Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app"), source: .applications)
    let drive = InstalledApp(bundleID: "com.google.drivefs", name: "Google Drive", url: URL(fileURLWithPath: "/Applications/Google Drive.app"), source: .applications)

    let home = URL(fileURLWithPath: "/Users/test")
    var prefs: LeftoverLocation { LeftoverLocation(kind: .preferences, domain: .user, url: home.appendingPathComponent("Library/Preferences")) }
    var groups: LeftoverLocation { LeftoverLocation(kind: .groupContainers, domain: .user, url: home.appendingPathComponent("Library/Group Containers")) }
    var support: LeftoverLocation { LeftoverLocation(kind: .applicationSupport, domain: .user, url: home.appendingPathComponent("Library/Application Support")) }

    func reason(_ matcher: AppMatcher, _ name: String, _ location: LeftoverLocation) -> String? {
        matcher.reason(forName: name, identifier: IdentifierParser.identifier(fromName: name), location: location)
    }

    @Test func ownIdentifiersAndHelpers() {
        let inventory = AppInventory(apps: [word, excel, mau, wordHelper, wordPaywall, wordErrors, excelErrors])
        let matcher = AppMatcher(app: word, inventory: inventory)
        #expect(reason(matcher, "com.microsoft.Word.plist", prefs) != nil)
        #expect(reason(matcher, "com.microsoft.Word.widgetextension", support) != nil)
        #expect(reason(matcher, "com.microsoft.Excel.plist", prefs) == nil)
        #expect(reason(matcher, "com.microsoft.autoupdate2.plist", prefs) == nil)
        #expect(reason(matcher, "com.microsoft.shared.plist", prefs) == nil, "shared vendor state is not one app's")
        #expect(reason(matcher, "com.microsoft.plist", prefs) == nil, "a bare vendor identifier is nobody's")
        #expect(reason(matcher, "com.microsoft.office.plist", prefs) == nil, "parent of an embedded helper only")
        #expect(reason(matcher, "com.microsoft.errorreporting", support) == nil, "embedded in Excel too")
        #expect(reason(matcher, "Microsoft", support) == nil, "vendor folder shared by every Microsoft app")
        #expect(reason(matcher, "UBF8T346G9.com.microsoft.oneauth", groups) == nil)
    }

    @Test func appGroupsAndTeamContainers() {
        let inventory = AppInventory(apps: [word, excel])
        let matcher = AppMatcher(app: word, inventory: inventory)
        #expect(reason(matcher, "UBF8T346G9.OfficeWordWidget", groups) != nil)
        #expect(reason(matcher, "UBF8T346G9.Office", groups) == nil, "Excel declares the same group, so it stays")
        #expect(reason(matcher, "UBF8T346G9.OfficeExcelWidget", groups) == nil)
    }

    @Test func shortForeignNamesDoNotBlockPrefixMatches() {
        let imager = InstalledApp(bundleID: "com.raspberrypi.rpi-imager", name: "Raspberry Pi Imager", url: URL(fileURLWithPath: "/Applications/Raspberry Pi Imager.app"), source: .applications)
        let odd = InstalledApp(bundleID: "com.example.odd", name: "…", url: URL(fileURLWithPath: "/Applications/Odd.app"), source: .applications)
        let matcher = AppMatcher(app: imager, inventory: AppInventory(apps: [imager, odd]))
        let caches = LeftoverLocation(kind: .caches, domain: .user, url: home.appendingPathComponent("Library/Caches"))
        #expect(reason(matcher, "Raspberry Pi", caches) != nil)
    }

    @Test func plainNamesAvoidAmbiguity() {
        let both = AppInventory(apps: [chrome, drive])
        let chromeOnly = AppInventory(apps: [chrome])
        #expect(reason(AppMatcher(app: chrome, inventory: both), "Google", support) == nil, "Google Drive also lives there")
        #expect(reason(AppMatcher(app: chrome, inventory: chromeOnly), "Google", support) != nil)
        #expect(reason(AppMatcher(app: chrome, inventory: both), "Google Chrome", support) != nil)
        #expect(reason(AppMatcher(app: chrome, inventory: both), "Chromium", support) == nil)
    }
}
