import AppKit
import ImageIO
import XCTest
@testable import NX2Apple
@testable import NXCore
@testable import NXModel

@MainActor final class AppIconTests: IsolatedDefaultsTestCase {
    private var fixture: ArtworkFixture!
    override func setUpWithError() throws { try super.setUpWithError(); fixture = try ArtworkFixture() }
    override func tearDownWithError() throws { fixture.cleanup(); fixture = nil; try super.tearDownWithError() }

    func testUnavailableDefaultHasNoEmptyTileOrBuildOverride() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.load()
        XCTAssertFalse(editor.tiles.contains { $0.source == .gameIcon })
        XCTAssertNil(editor.selectedFile)
        XCTAssertEqual(editor.gridColumns, 4)
        XCTAssertFalse(editor.isDirty)
        XCTAssertFalse(editor.canReset(.icon))
        XCTAssertNil(try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
    }

    func testSaveKeepsSourceAndSquarePNGAfterOriginalIsDeletedAndResetRemovesBoth() async throws {
        let file = try fixture.chosenImage(width: 1600, height: 900)
        let editor = fixture.editor(slot: .icon)
        await editor.load()
        await editor.importFile(file)
        await editor.measureSelected()
        XCTAssertEqual(editor.framingBand, CGSize(width: 1, height: 1))
        XCTAssertTrue(editor.needsFraming)
        editor.setFocus(ArtworkFocus(x: 1, y: 0.5))
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(editor.save(to: fixture.library))
        let saved = fixture.library.games[0].artwork
        XCTAssertNil(saved.hero)
        XCTAssertNil(saved.thumbnail)
        XCTAssertEqual(saved.icon?.focus.x, 1)
        XCTAssertEqual(saved.importedFiles.count, 2)
        let icon = try XCTUnwrap(fixture.library.appIcon(for: fixture.titleID, basePath: ""))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: icon) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1024)
        XCTAssertEqual(image.height, 1024)
        let reload = GameLibrary(file: fixture.temporary.appendingPathComponent("library.json"), artwork: fixture.artwork)
        XCTAssertEqual(reload.games[0].artwork, saved)
        let reset = fixture.editor(slot: .icon)
        reset.reset(.icon)
        XCTAssertTrue(reset.save(to: fixture.library))
        XCTAssertNil(try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.customDirectory.path), [])
    }

    func testCancelRemovesImportedIconAndLeavesHeroAlone() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.importFile(try fixture.chosenImage(width: 1500))
        editor.cancel()
        XCTAssertEqual(fixture.library.games[0].artwork, GameArtwork())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.customDirectory.path), [])
    }

    func testFramingChangesPNGAndCancelPreservesSavedFiles() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.importFile(try fixture.chosenImage(width: 1600, height: 800))
        editor.setFocus(ArtworkFocus(x: 0, y: 0.5))
        XCTAssertTrue(editor.save(to: fixture.library))
        let before = fixture.library.games[0].artwork
        let changed = fixture.editor(slot: .icon)
        changed.setFocus(ArtworkFocus(x: 1, y: 0.5))
        XCTAssertTrue(changed.save(to: fixture.library))
        let after = fixture.library.games[0].artwork
        XCTAssertNotEqual(after.iconFile, before.iconFile)
        XCTAssertEqual(after.icon?.source, before.icon?.source)
        let cancelled = fixture.editor(slot: .icon)
        cancelled.setFocus(.center)
        cancelled.cancel()
        XCTAssertEqual(fixture.library.games[0].artwork, after)
        for name in after.importedFiles { XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.customDirectory.appendingPathComponent(name).path)) }
    }

    func testSavingWhileAnotherTabIsOpenStillRendersTheIcon() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.importFile(try fixture.chosenImage(width: 1200))
        editor.slot = .hero
        XCTAssertTrue(editor.save(to: fixture.library))
        XCTAssertNotNil(try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
    }

    func testMissingSavedPNGIsAnErrorAndDoesNotFallBackToTheGamesIcon() throws {
        var artwork = GameArtwork(icon: ArtworkChoice(source: .eshopIcon))
        artwork.iconFile = "gone.png"
        XCTAssertTrue(fixture.library.setArtwork(artwork, for: fixture.gameID))
        XCTAssertThrowsError(try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
        artwork.iconFile = "../outside.png"
        XCTAssertTrue(fixture.library.setArtwork(artwork, for: fixture.gameID))
        XCTAssertThrowsError(try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
    }

    func testUnreadableSourceCannotSaveAndCancelCleansTheCopy() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.importFile(try fixture.chosenImage(width: 1200))
        let file = try XCTUnwrap(editor.selectedFile)
        try Data("broken image".utf8).write(to: file)
        XCTAssertFalse(editor.save(to: fixture.library))
        XCTAssertEqual(fixture.library.games[0].artwork, GameArtwork())
        XCTAssertTrue(editor.isDirty)
        XCTAssertNotNil(editor.notice)
        editor.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testEshopSelectionSurvivesOfflineAndMissingRenderedFileCanBeRepaired() async throws {
        let file = try fixture.chosenImage(width: 1024, height: 1024)
        var env = fixture.environment()
        env.media = { _, _ in .loaded(ArtworkStore.Media(screenshots: [], icon: "icon")) }
        env.candidate = { _, _ in file }
        env.cachedCandidate = { source, _ in source == .eshopIcon ? file : nil }
        let editor = ArtworkEditor(game: fixture.game, slot: .icon, artworkDirectory: fixture.artwork, env: env, labels: { L10n.string($0, .en) })
        await editor.load()
        XCTAssertTrue(editor.select(try XCTUnwrap(editor.tiles.first { $0.source == .eshopIcon })))
        XCTAssertTrue(editor.save(to: fixture.library))
        XCTAssertEqual(fixture.game.artwork.icon?.source, .eshopIcon)
        let png = try XCTUnwrap(fixture.library.appIcon(for: fixture.titleID, basePath: ""))
        try FileManager.default.removeItem(atPath: png)
        env.media = { _, _ in .offline }
        let reopened = ArtworkEditor(game: fixture.game, slot: .icon, artworkDirectory: fixture.artwork, env: env, labels: { L10n.string($0, .en) })
        await reopened.load()
        XCTAssertEqual(reopened.selectedFile, file)
        XCTAssertTrue(reopened.isDirty, "Save repairs the missing PNG even with the same source")
        XCTAssertTrue(reopened.save(to: fixture.library))
        XCTAssertNotNil(try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
    }

    func testLibraryWriteFailureKeepsTheDraftAndCancelRemovesBothNewCopies() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.importFile(try fixture.chosenImage(width: 1200))
        let libraryFile = fixture.temporary.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: libraryFile)
        try FileManager.default.createDirectory(at: libraryFile, withIntermediateDirectories: false)
        XCTAssertFalse(editor.save(to: fixture.library))
        XCTAssertEqual(fixture.library.games[0].artwork, GameArtwork())
        XCTAssertTrue(editor.isDirty)
        XCTAssertNotNil(editor.notice)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.customDirectory.path).count, 2)
        editor.cancel()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.customDirectory.path), [])
    }

    func testResettingIconKeepsTheSourceUsedByHero() async throws {
        let file = try fixture.chosenImage(width: 1800)
        let hero = fixture.editor()
        await hero.importFile(file)
        XCTAssertTrue(hero.save(to: fixture.library))
        let savedHero = fixture.game.artwork.hero
        let icon = fixture.editor(slot: .icon)
        XCTAssertFalse(icon.tiles.contains { $0.source == savedHero?.source }, "a hero import is not an icon choice until explicitly imported there")
        await icon.importFile(file)
        XCTAssertEqual(icon.draft.icon?.source, savedHero?.source)
        XCTAssertTrue(icon.save(to: fixture.library))
        let reset = fixture.editor(slot: .icon)
        reset.reset(.icon)
        XCTAssertTrue(reset.save(to: fixture.library))
        XCTAssertEqual(fixture.game.artwork.hero, savedHero)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.customDirectory.path).count, 1)
    }

    func testIconImportsDoNotAppearOnHeroOrThumbnail() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.importFile(try fixture.chosenImage(width: 1200))
        let source = try XCTUnwrap(editor.draft.icon?.source)
        XCTAssertTrue(editor.tiles.contains { $0.source == source })
        editor.slot = .hero
        XCTAssertFalse(editor.tiles.contains { $0.source == source })
        editor.slot = .thumbnail
        XCTAssertFalse(editor.tiles.contains { $0.source == source })
        editor.slot = .icon
        XCTAssertTrue(editor.tiles.contains { $0.source == source })
        editor.cancel()
    }

    func testAvailableOriginalIconIsShownAndCanResetAChoice() async throws {
        let file = try fixture.chosenImage(width: 1024, height: 1024)
        var env = fixture.environment()
        env.gameIcon = { _ in file }
        let editor = ArtworkEditor(game: fixture.game, slot: .icon, artworkDirectory: fixture.artwork, env: env, labels: { L10n.string($0, .en) })
        await editor.importFile(file)
        XCTAssertTrue(editor.canReset(.icon))
        let original = try XCTUnwrap(editor.tiles.first { $0.source == .gameIcon })
        XCTAssertEqual(original.file, file)
        XCTAssertTrue(editor.select(original))
        XCTAssertNil(editor.draft.icon)
        XCTAssertFalse(editor.isDirty)
        editor.cancel()
    }

    func testIconKeyboardNavigationUsesTheCompactFourColumnGrid() async throws {
        let editor = fixture.editor(slot: .icon)
        for n in 0..<6 {
            await editor.importFile(try fixture.chosenImage(width: 1200, height: 1200, name: "icon-\(n).png", hue: CGFloat(n) / 6))
        }
        XCTAssertEqual(editor.tiles.count, 6)
        editor.select(editor.tiles[0])
        editor.move(.right)
        XCTAssertEqual(editor.cursor, 1)
        editor.move(.down)
        XCTAssertEqual(editor.cursor, 5)
        editor.move(.up)
        XCTAssertEqual(editor.cursor, 1)
        editor.cancel()
    }

    func testSessionWiresIconChoiceBeforeAnyWindowOpens() async throws {
        let editor = fixture.editor(slot: .icon)
        await editor.importFile(try fixture.chosenImage(width: 1200))
        XCTAssertTrue(editor.save(to: fixture.library))
        let session = LauncherSession(stores: LauncherStores(defaults: testDefaults), library: fixture.library)
        XCTAssertEqual(try session.stores.build.appIcon(fixture.titleID, ""), try fixture.library.appIcon(for: fixture.titleID, basePath: ""))
    }
}
