import AppKit
import ImageIO
import XCTest
@testable import NX2Apple
@testable import NXCore
@testable import NXModel

/// The App icon tab when things go wrong: writes that fail, downloads that arrive late, and the crop read back from the PNG.
@MainActor final class AppIconBreakTests: IsolatedDefaultsTestCase {
    private var fixture: ArtworkFixture!
    override func setUpWithError() throws { try super.setUpWithError(); fixture = try ArtworkFixture() }
    override func tearDownWithError() throws {
        for path in [fixture.temporary.path, fixture.customDirectory.path] { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
        fixture.cleanup(); fixture = nil
        try super.tearDownWithError()
    }

    private func savedIcon(width: Int = 1600, height: Int = 900, name: String = "a.png", hue: CGFloat = 0.6) async throws -> String {
        let editor = fixture.editor(slot: .icon)
        await editor.load()
        await editor.importFile(try fixture.chosenImage(width: width, height: height, name: name, hue: hue))
        XCTAssertTrue(editor.save(to: fixture.library))
        return try XCTUnwrap(fixture.library.appIcon(for: fixture.titleID, basePath: ""))
    }

    /// Top and bottom halves (or left and right) in two colours, to read back which part the PNG kept.
    private func halves(_ name: String, width: Int, height: Int, vertical: Bool) throws -> URL {
        let url = fixture.temporary.appendingPathComponent(name)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.red.setFill()   // the top half (AppKit's y goes up) or the left half
        (vertical ? NSRect(x: 0, y: height / 2, width: width, height: height / 2) : NSRect(x: 0, y: 0, width: width / 2, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private func centreIsRed(_ path: String) throws -> Bool {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))))
        let colour = try XCTUnwrap(rep.colorAt(x: 512, y: 512)?.usingColorSpace(.deviceRGB))
        return colour.redComponent > 0.5 && colour.blueComponent < 0.5
    }

    // ---- Writes ----

    func testAFailedSaveKeepsThePreviousIconAndCancelKeepsItsPNG() async throws {
        let before = try await savedIcon()
        let json = fixture.temporary.appendingPathComponent("library.json")
        let written = try Data(contentsOf: json)
        let editor = fixture.editor(slot: .icon)
        await editor.load()
        await editor.importFile(try fixture.chosenImage(width: 1200, height: 1200, name: "b.png", hue: 0.1))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.temporary.path)
        XCTAssertFalse(editor.save(to: fixture.library))
        guard case .error? = editor.notice else { return XCTFail("the panel says the save failed") }
        XCTAssertEqual(try Data(contentsOf: json), written)
        XCTAssertEqual(try fixture.library.appIcon(for: fixture.titleID, basePath: ""), before, "the build still gets the saved icon")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.temporary.path)
        editor.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: before), "Cancel after a failed Save keeps the saved icon's PNG")
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: fixture.customDirectory.path))
        XCTAssertEqual(left, fixture.game.artwork.importedFiles, "and removes only what this session made")
    }

    func testAnIconFolderThatCannotBeWrittenLeavesTheLibraryAsItWas() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.load()
        await editor.importFile(try fixture.chosenImage(width: 1600, height: 900))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.customDirectory.path)
        XCTAssertFalse(editor.save(to: fixture.library))
        guard case .error? = editor.notice else { return XCTFail("the panel says the icon could not be made") }
        XCTAssertEqual(fixture.game.artwork, GameArtwork())
        XCTAssertTrue(editor.isDirty, "Save stays on to try again")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.customDirectory.path)
        XCTAssertTrue(editor.save(to: fixture.library))
        XCTAssertNotNil(try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
    }

    func testASavedIconWhosePNGWasDeletedIsMadeAgainBySave() async throws {
        let png = try await savedIcon()
        try FileManager.default.removeItem(atPath: png)
        XCTAssertThrowsError(try fixture.library.appIcon(for: fixture.titleID, basePath: ""), "the build stops with a message, never the wrong icon")
        let editor = fixture.editor(slot: .icon)
        await editor.load()
        XCTAssertTrue(editor.isDirty, "Save is offered to make it again")
        XCTAssertTrue(editor.save(to: fixture.library))
        XCTAssertEqual(try fixture.library.appIcon(for: fixture.titleID, basePath: ""), png, "the same crop gives the same file")
    }

    func testTheIconSharingTheHerosFileSurvivesAHeroReset() async throws {
        let shared = try fixture.chosenImage(width: 1600, height: 900)
        let editor = fixture.editor()
        await editor.load()
        await editor.importFile(shared)
        editor.slot = .icon
        await editor.importFile(shared)
        XCTAssertTrue(editor.save(to: fixture.library))
        let png = try XCTUnwrap(fixture.library.appIcon(for: fixture.titleID, basePath: ""))
        let reset = fixture.editor()
        await reset.load()
        reset.reset(.hero)
        XCTAssertTrue(reset.save(to: fixture.library))
        XCTAssertTrue(FileManager.default.fileExists(atPath: png))
        guard case .imported(let name)? = fixture.game.artwork.icon?.source else { return XCTFail("the icon keeps its source") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.customDirectory.appendingPathComponent(name).path), "and the source the icon was cut from")
    }

    // ---- The rebuild offer ----

    private func builtApp() throws -> String {
        let app = fixture.temporary.appendingPathComponent("Hades.app")
        let executables = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        for name in ["nxnative", "dmhost"] {
            try FileManager.default.createSymbolicLink(at: executables.appendingPathComponent(name), withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        }
        let info: [String: Any] = ["DMTitleID": fixture.titleID, "CFBundleDisplayName": "Hades", "CFBundleExecutable": "nxnative", "CFBundleIdentifier": TestPreferences.domain(in: fixture.temporary, "icon")]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app.path
    }

    private func saveIcon(reset: Bool = false) async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.load()
        if reset { editor.reset(.icon) } else { await editor.importFile(try fixture.chosenImage(width: 1600, height: 900)) }
        XCTAssertTrue(editor.save(to: fixture.library))
    }

    func testARebuildIsOfferedOnlyWhenTheSavedIconIsNotTheOneInTheBuiltApp() async throws {
        fixture.library.recordCompletedApp(path: try builtApp(), for: fixture.gameID)   // built with the game's own icon
        XCTAssertFalse(fixture.game.iconNeedsRebuild)
        try await saveIcon()
        XCTAssertTrue(fixture.game.iconNeedsRebuild, "a new icon the app does not show yet")
        try await saveIcon(reset: true)
        XCTAssertFalse(fixture.game.iconNeedsRebuild, "back to the icon the app already has: nothing to rebuild")

        try await saveIcon()
        let built = fixture.game.artwork.iconFile
        fixture.library.recordCompletedApp(path: fixture.game.appPath, icon: built, for: fixture.gameID)
        XCTAssertFalse(fixture.game.iconNeedsRebuild)
        try await saveIcon(reset: true)
        XCTAssertTrue(fixture.game.iconNeedsRebuild, "the app was built with the custom icon, so going back needs a rebuild")
        let reload = GameLibrary(file: fixture.temporary.appendingPathComponent("library.json"), artwork: fixture.artwork)
        XCTAssertEqual(reload.games[0].macAppIcon, built, "kept across launches")
    }

    func testAGameThatIsNotBuiltNeverAsksForARebuild() async throws {
        try await saveIcon()
        XCTAssertFalse(fixture.game.iconNeedsRebuild, "its first build takes the icon")
    }

    // ---- Downloads ----

    private func eShopEnvironment(hold: @escaping () -> Bool) -> ArtworkEditorEnvironment {
        var env = fixture.environment()
        let icon = fixture.temporary.appendingPathComponent("shop-icon.jpg")
        env.media = { _, _ in .loaded(ArtworkStore.Media(screenshots: [], icon: "shop")) }
        env.candidate = { source, _ in
            while hold() { try await Task.sleep(nanoseconds: 10_000_000) }
            guard source == .eshopIcon else { throw URLError(.cannotConnectToHost) }
            try ArtworkFixture.picture(icon, width: 1024, height: 1024, hue: 0.4, label: "eShop icon")
            return icon
        }
        return env
    }

    func testTheEShopIconCannotBeChosenBeforeItArrivesNorAfterCancel() async throws {
        var held = true
        let editor = ArtworkEditor(game: fixture.game, slot: .icon, artworkDirectory: fixture.artwork, env: eShopEnvironment { held }, labels: { $0 })
        let loading = Task { await editor.load() }
        for _ in 0..<100 where !editor.tiles.contains(where: { $0.source == .eshopIcon }) { try await Task.sleep(nanoseconds: 10_000_000) }
        let tile = try XCTUnwrap(editor.tiles.first { $0.source == .eshopIcon })
        XCTAssertFalse(editor.select(tile), "a placeholder is not a choice")
        editor.slot = .hero
        XCTAssertFalse(editor.tiles.contains { $0.source == .eshopIcon }, "the hero never offers the icon")
        editor.cancel()
        held = false
        await loading.value
        XCTAssertEqual(fixture.game.artwork, GameArtwork())
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: fixture.customDirectory.path)) ?? [], [], "nothing is copied into the game's folder")
    }

    func testTheEShopIconArrivingWhileAnotherTabIsOpenLeavesThatTabsChoiceAlone() async throws {
        var held = true
        let editor = ArtworkEditor(game: fixture.game, slot: .icon, artworkDirectory: fixture.artwork, env: eShopEnvironment { held }, labels: { $0 })
        let loading = Task { await editor.load() }
        try await Task.sleep(nanoseconds: 50_000_000)
        editor.slot = .thumbnail
        held = false
        await loading.value
        XCTAssertNil(editor.draft.thumbnail)
        XCTAssertNil(editor.draft.icon, "an arrival chooses nothing")
        editor.slot = .icon
        let tile = try XCTUnwrap(editor.tiles.first { $0.source == .eshopIcon })
        XCTAssertTrue(editor.select(tile))
        XCTAssertTrue(editor.save(to: fixture.library))
        XCTAssertEqual(fixture.game.artwork.icon?.source, .eshopIcon)
        XCTAssertNil(fixture.game.artwork.thumbnail)
    }

    // ---- The same crop everywhere ----

    func testThePNGKeepsThePartTheFocusPointsAt() async throws {
        for (vertical, focus, red) in [(true, ArtworkFocus(x: 0.5, y: 0), true), (true, ArtworkFocus(x: 0.5, y: 1), false),
                                       (false, ArtworkFocus(x: 0, y: 0.5), true), (false, ArtworkFocus(x: 1, y: 0.5), false)] {
            let file = try halves("halves-\(vertical)-\(focus.x)-\(focus.y).png", width: vertical ? 900 : 1600, height: vertical ? 1600 : 900, vertical: vertical)
            let png = try AppIconImage.render(file, focus: focus, into: fixture.temporary.appendingPathComponent("out"))
            XCTAssertEqual(try centreIsRed(png.path), red, "\(vertical ? "tall" : "wide") image, focus \(focus)")
            let shown = ArtworkFraming.offset(image: CGSize(width: vertical ? 900 : 1600, height: vertical ? 1600 : 900), band: CGSize(width: 64, height: 64), focus: focus.point)
            XCTAssertEqual(vertical ? shown.height > 0 : shown.width > 0, red, "the preview moves the image the same way")
        }
    }

    // ---- The same move with every input ----

    func testVoiceOverMovesTheIconsFramingOnTheAxisThatIsCropped() async throws {
        for (width, height, horizontal) in [(1600, 900, true), (900, 1600, false)] {
            let editor = fixture.editor(slot: .icon)
            await editor.load()
            await editor.importFile(try fixture.chosenImage(width: width, height: height, name: "\(width)x\(height).png"))
            await editor.measureSelected()
            editor.adjustFocus(increment: true)
            XCTAssertEqual(horizontal ? editor.focus.x > 0.5 : editor.focus.y > 0.5, true, "\(width)×\(height)")
            XCTAssertEqual(horizontal ? editor.focus.y : editor.focus.x, 0.5, "the other axis stays")
            editor.cancel()
        }
    }

    func testArrowsOnTheIconGridStayInsideIt() async throws {
        var env = eShopEnvironment { false }
        let game = fixture.temporary.appendingPathComponent("game-icon.jpg")
        try ArtworkFixture.picture(game, width: 256, height: 256, hue: 0.2, label: "Game")
        env.gameIcon = { _ in game }
        let editor = ArtworkEditor(game: fixture.game, slot: .icon, artworkDirectory: fixture.artwork, env: env, labels: { $0 })
        await editor.load()
        XCTAssertEqual(editor.tiles.map(\.source), [.gameIcon, .eshopIcon])
        editor.move(.right); editor.move(.right); editor.move(.right); editor.move(.down)
        XCTAssertEqual(editor.cursor, 1)
        XCTAssertEqual(editor.draft.icon?.source, .eshopIcon)
        editor.move(.left); editor.move(.left); editor.move(.up)
        XCTAssertEqual(editor.cursor, 0)
        XCTAssertNil(editor.draft.icon, "the game's own icon is the default, not a saved choice")
    }
}
