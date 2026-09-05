import Testing
@testable import DebrisKit

struct IdentifierParserTests {
    @Test func stripsTeamAndGroupPrefixes() {
        #expect(IdentifierParser.identifier(fromName: "4C6364ACXT.com.parallels.Desktop") == "com.parallels.Desktop")
        #expect(IdentifierParser.identifier(fromName: "group.com.facebook.Messenger") == "com.facebook.Messenger")
        #expect(IdentifierParser.identifier(fromName: "com.vivaldi.Vivaldi.plist") == "com.vivaldi.Vivaldi")
        #expect(IdentifierParser.identifier(fromName: "com.hnc.Discord.binarycookies") == "com.hnc.Discord")
        #expect(IdentifierParser.identifier(fromName: "com.mimestream.Mimestream.savedState") == "com.mimestream.Mimestream")
    }

    @Test func dropsByHostSuffix() {
        #expect(IdentifierParser.identifier(fromName: "com.microsoft.VSCode.ShipIt.4D2AF975-BCF7-5E24-BFBF-30874BB84083.plist") == "com.microsoft.VSCode.ShipIt")
    }

    @Test func rejectsPlainNames() {
        #expect(IdentifierParser.identifier(fromName: "Google") == nil)
        #expect(IdentifierParser.identifier(fromName: "tabby-updater") == nil)
        #expect(IdentifierParser.identifier(fromName: ".vscode") == nil)
        #expect(IdentifierParser.identifier(fromName: "Battle.net") == nil)
        #expect(IdentifierParser.identifier(fromName: "calibre-ebook.com") == nil)
    }

    @Test func acceptsUnusualButValidIdentifiers() {
        #expect(IdentifierParser.identifier(fromName: "pro.betterdisplay.BetterDisplay") == "pro.betterdisplay.BetterDisplay")
        #expect(IdentifierParser.identifier(fromName: "imagetasks.iStatisticaSensors") == nil)
        #expect(IdentifierParser.identifier(fromName: "desktop.WhatsApp") == "desktop.WhatsApp")
    }

    @Test func vendorDerivation() {
        #expect(Identifier.vendor(of: "com.microsoft.Outlook") == "com.microsoft")
        #expect(Identifier.vendor(of: "io.github.alice.Tool") == "io.github.alice")
        #expect(Identifier.vendor(of: "desktop.WhatsApp") == "desktop.whatsapp")
    }
}

struct PrefixOrderTests {
    @Test func groupBeforeTeam() {
        #expect(IdentifierParser.identifier(fromName: "group.U5SR49N3PT.only.if.Amphetamine") == "only.if.Amphetamine")
        #expect(IdentifierParser.teamPrefix(of: "group.U5SR49N3PT.only.if.Amphetamine") == "U5SR49N3PT")
        #expect(IdentifierParser.teamPrefix(of: "UBF8T346G9.Office") == "UBF8T346G9")
        #expect(IdentifierParser.teamPrefix(of: "com.foo.Bar") == nil)
    }
}
