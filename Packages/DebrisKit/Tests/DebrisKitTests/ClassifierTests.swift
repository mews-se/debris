import Foundation
import Testing
@testable import DebrisKit

struct ClassifierTests {
    let inventory = AppInventory(apps: [
        InstalledApp(bundleID: "com.microsoft.Outlook", name: "Microsoft Outlook", url: URL(fileURLWithPath: "/Applications/Microsoft Outlook.app"), source: .applications),
        InstalledApp(bundleID: "com.openai.codex", name: "ChatGPT", url: URL(fileURLWithPath: "/Applications/ChatGPT.app"), source: .applications),
        InstalledApp(bundleID: "org.filezilla-project.filezilla", name: "FileZilla", url: URL(fileURLWithPath: "/Applications/FileZilla.app"), source: .applications),
        InstalledApp(bundleID: "in.vikramrao.Lan-Status", name: "Ethernet Status", url: URL(fileURLWithPath: "/Applications/Ethernet Status.app"), source: .applications),
    ], homebrewFormulae: ["btop", "fastfetch"])

    var classifier: Classifier { Classifier(inventory: inventory) }
    let home = URL(fileURLWithPath: "/Users/test")
    var appSupport: LeftoverLocation { LeftoverLocation(kind: .applicationSupport, domain: .user, url: home.appendingPathComponent("Library/Application Support")) }
    var prefs: LeftoverLocation { LeftoverLocation(kind: .preferences, domain: .user, url: home.appendingPathComponent("Library/Preferences")) }
    var dotfiles: LeftoverLocation { LeftoverLocation(kind: .dotfiles, domain: .user, url: home) }
    var config: LeftoverLocation { LeftoverLocation(kind: .config, domain: .user, url: home.appendingPathComponent(".config")) }

    func classify(_ name: String, in location: LeftoverLocation) -> Classification? {
        classifier.classify(name: name, identifier: IdentifierParser.identifier(fromName: name), location: location)
    }

    @Test func installedAppsAreNotLeftovers() {
        #expect(classify("com.microsoft.Outlook.plist", in: prefs) == nil)
        #expect(classify("com.microsoft.Outlook.CalendarWidget", in: appSupport) == nil)
        #expect(classify("com.apple.finder.plist", in: prefs) == nil)
    }

    @Test func sameVendorIsMediumConfidence() {
        let result = classify("com.microsoft.VSCode.plist", in: prefs)
        #expect(result?.ownership == .vendor("com.microsoft"))
        #expect(result?.confidence == .medium)
    }

    @Test func unknownIdentifierIsHighConfidence() {
        let result = classify("com.vivaldi.Vivaldi.plist", in: prefs)
        #expect(result?.ownership == .unknown)
        #expect(result?.confidence == .high)
    }

    @Test func sdkDomainsAreProtected() {
        #expect(classify("com.revenuecat.user_defaults.plist", in: prefs) == nil)
        #expect(classify("com.github.Electron.plist", in: prefs) == nil)
    }

    @Test func dotfilesKnowTheirOwners() {
        #expect(classify(".putty", in: dotfiles) == nil, "FileZilla owns ~/.putty")
        #expect(classify(".codex", in: dotfiles) == nil, "ChatGPT.app is com.openai.codex")
        #expect(classify(".ssh", in: dotfiles) == nil)
        let lmstudio = classify(".lmstudio", in: dotfiles)
        #expect(lmstudio?.confidence == .high)
        let unknown = classify(".somethingelse", in: dotfiles)
        #expect(unknown?.confidence == .medium)
    }

    @Test func configFoldersMatchHomebrewFormulae() {
        #expect(classify("btop", in: config) == nil)
        #expect(classify("neofetch", in: config)?.confidence == .medium)
    }

    @Test func plainNamesUseFuzzyMatchingCarefully() {
        #expect(classify("Microsoft Outlook", in: appSupport) == nil)
        #expect(classify("Vivaldi", in: appSupport)?.confidence == .high)
        #expect(classify("askpermissiond", in: appSupport) == nil)
        #expect(classify("CrashReporter", in: appSupport) == nil)
    }

    @Test func groupingByVendor() {
        let items = [
            LeftoverItem(url: home.appendingPathComponent("a"), location: prefs, identifier: "com.parallels.Desktop",
                         classification: Classification(ownership: .unknown, confidence: .high), modified: nil, size: 10),
            LeftoverItem(url: home.appendingPathComponent("b"), location: prefs, identifier: "com.parallels.toolbox",
                         classification: Classification(ownership: .unknown, confidence: .high), modified: nil, size: 5),
            LeftoverItem(url: home.appendingPathComponent("Vivaldi"), location: appSupport, identifier: nil,
                         classification: Classification(ownership: .unknown, confidence: .high), modified: nil, size: 100),
        ]
        let groups = Grouping.groups(from: items)
        #expect(groups.count == 2)
        #expect(groups.first?.title == "Vivaldi")
        #expect(groups.last?.title == "Parallels")
        #expect(groups.last?.totalSize == 15)
    }
}

struct TeamAndGroupTests {
    let inventory = AppInventory(apps: [
        InstalledApp(bundleID: "com.microsoft.Excel", name: "Microsoft Excel", url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app"),
                     teamID: "UBF8T346G9", appGroups: ["UBF8T346G9.Office"], source: .applications),
        InstalledApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", url: URL(fileURLWithPath: "/Applications/WhatsApp.app"),
                     teamID: "57T9237FN3", appGroups: ["group.net.whatsapp.family"], source: .applications),
        InstalledApp(bundleID: "us.zoom.xos", name: "zoom.us", url: URL(fileURLWithPath: "/Applications/zoom.us.app"), source: .applications),
    ])
    let home = URL(fileURLWithPath: "/Users/test")

    @Test func teamPrefixedContainersBelongToInstalledTeam() {
        let location = LeftoverLocation(kind: .groupContainers, domain: .user, url: home.appendingPathComponent("Library/Group Containers"))
        let classifier = Classifier(inventory: inventory)
        #expect(classifier.classify(name: "UBF8T346G9.OfficeWordWidget", identifier: nil, location: location) == nil)
        #expect(classifier.classify(name: "group.net.whatsapp.family", identifier: "net.whatsapp.family", location: location) == nil)
        #expect(classifier.classify(name: "ABCDEFGHIJ.Something", identifier: nil, location: location)?.confidence == .high)
    }

    @Test func plainPreferenceNamesAreLowConfidence() {
        let prefs = LeftoverLocation(kind: .preferences, domain: .user, url: home.appendingPathComponent("Library/Preferences"))
        let classifier = Classifier(inventory: inventory)
        #expect(classifier.classify(name: "ZoomChat.plist", identifier: nil, location: prefs)?.confidence == .low)
        #expect(classifier.classify(name: "SomethingOdd.plist", identifier: nil, location: prefs)?.confidence == .low)
        #expect(classifier.classify(name: "TokenBucketRateLimiter.plist", identifier: nil, location: prefs) == nil)
    }
}

struct NameOwnershipTests {
    let inventory = AppInventory(apps: [
        InstalledApp(bundleID: "com.openai.codex", name: "ChatGPT", url: URL(fileURLWithPath: "/Applications/ChatGPT.app"), source: .applications),
        InstalledApp(bundleID: "com.raspberrypi.rpi-imager", name: "Raspberry Pi Imager", url: URL(fileURLWithPath: "/Applications/Raspberry Pi Imager.app"), source: .applications),
        InstalledApp(bundleID: "org.torproject.torbrowser", name: "Tor Browser", url: URL(fileURLWithPath: "/Applications/Tor Browser.app"), source: .applications),
    ])
    let caches = LeftoverLocation(kind: .caches, domain: .user, url: URL(fileURLWithPath: "/Users/test/Library/Caches"))

    @Test func foldersNamedAfterInstalledAppsAreOwned() {
        let classifier = Classifier(inventory: inventory)
        #expect(classifier.classify(name: "Codex", identifier: nil, location: caches) == nil)
        #expect(classifier.classify(name: "Raspberry Pi", identifier: nil, location: caches) == nil)
        #expect(classifier.classify(name: "TorBrowser-Data", identifier: nil, location: caches) == nil)
        #expect(classifier.classify(name: "Vivaldi", identifier: nil, location: caches)?.confidence == .high)
    }

    @Test func qtStylePreferencesMatchTheAppName() {
        let classifier = Classifier(inventory: inventory)
        let prefs = LeftoverLocation(kind: .preferences, domain: .user, url: URL(fileURLWithPath: "/Users/test/Library/Preferences"))
        #expect(classifier.classify(name: "com.raspberrypi.Raspberry Pi Imager.plist", identifier: "com.raspberrypi.Raspberry Pi Imager", location: prefs) == nil)
        #expect(classifier.classify(name: "com.raspberrypi.Something Else.plist", identifier: "com.raspberrypi.Something Else", location: prefs)?.confidence == .medium)
    }
}

struct CommandOwnershipTests {
    let home = URL(fileURLWithPath: "/Users/test")
    let inventory = AppInventory(apps: [], homebrewFormulae: ["node"], commands: ["ykman", "oh-my-posh"])

    @Test func toolsOnThePathOwnTheirState() {
        let classifier = Classifier(inventory: inventory)
        let localShare = LeftoverLocation(kind: .localShare, domain: .user, url: home.appendingPathComponent(".local/share"))
        let cache = LeftoverLocation(kind: .userCache, domain: .user, url: home.appendingPathComponent(".cache"))
        #expect(classifier.classify(name: "ykman", identifier: nil, location: localShare) == nil)
        #expect(classifier.classify(name: "oh-my-posh", identifier: nil, location: cache) == nil)
        #expect(classifier.classify(name: "prisma", identifier: nil, location: cache)?.confidence == .medium)
    }

    @Test func nodeGypCacheBelongsToNode() {
        let caches = LeftoverLocation(kind: .caches, domain: .user, url: home.appendingPathComponent("Library/Caches"))
        #expect(Classifier(inventory: inventory).classify(name: "node-gyp", identifier: nil, location: caches) == nil)
        let without = Classifier(inventory: AppInventory(apps: []))
        #expect(without.classify(name: "node-gyp", identifier: nil, location: caches)?.confidence == .high)
    }
}

struct EdgeCaseTests {
    let inventory = AppInventory(apps: [
        InstalledApp(bundleID: "com.coconut-flavour.coconutBattery", name: "coconutBattery", url: URL(fileURLWithPath: "/Applications/coconutBattery.app"), source: .applications),
        InstalledApp(bundleID: "com.apphousekitchen.aldente-pro", name: "AlDente", url: URL(fileURLWithPath: "/Applications/AlDente.app"), source: .applications),
    ], homebrewFormulae: ["beszel-agent"])
    let home = URL(fileURLWithPath: "/Users/test")

    @Test func hyphenatedVendorsAndSeparators() {
        let classifier = Classifier(inventory: inventory)
        let scripts = LeftoverLocation(kind: .applicationScripts, domain: .user, url: home.appendingPathComponent("Library/Application Scripts"))
        let prefs = LeftoverLocation(kind: .preferences, domain: .user, url: home.appendingPathComponent("Library/Preferences"))
        #expect(classifier.classify(name: "group.coconut-flavour.coconutBattery", identifier: nil, location: scripts)?.confidence == .medium)
        #expect(classifier.classify(name: "com.apphousekitchen.aldente-pro_stats.sqlite3", identifier: "com.apphousekitchen.aldente-pro_stats", location: prefs) == nil)
        #expect(classifier.classify(name: "com.apple.clock~iosmac.savedState", identifier: nil, location: prefs) == nil)
        #expect(classifier.classify(name: "com.launchdarkly.client.abc=.def+ghi", identifier: nil, location: prefs) == nil)
        #expect(classifier.classify(name: "askpermissiond", identifier: nil, location: prefs) == nil)
    }

    @Test func homebrewServices() {
        let classifier = Classifier(inventory: inventory)
        let agents = LeftoverLocation(kind: .launchAgents, domain: .user, url: home.appendingPathComponent("Library/LaunchAgents"))
        #expect(classifier.classify(name: "homebrew.mxcl.beszel-agent.plist", identifier: nil, location: agents) == nil)
        #expect(classifier.classify(name: "homebrew.mxcl.redis.plist", identifier: nil, location: agents)?.confidence == .high)
    }
}
