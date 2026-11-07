import XCTest
@testable import NX2Apple
@testable import NXCore
@testable import NXModel

@MainActor final class AppIconAdversarialTests: IsolatedDefaultsTestCase {
    private var fixture: ArtworkFixture!
    override func tearDownWithError() throws { fixture?.cleanup(); fixture = nil; try super.tearDownWithError() }

    // The user sees: the Mac app of game B is built with the stock icon (or another entry's) because an earlier entry A shares B's base path.
    func testAppIconLookupMatchesTheTitleIDBeforeTheBasePath() throws {
        fixture = try ArtworkFixture(saved: #","inputs":{"base":["/games/shared.nsp"]}"#, others: [(titleID: "0100AAAA00000000", name: "Other")])
        let other = fixture.library.games[1]
        let dir = ArtworkStore.customDirectory(for: other.id, in: fixture.artwork)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = String(repeating: "a", count: 64) + ".png"
        try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        var artwork = GameArtwork(icon: ArtworkChoice(source: .eshopIcon)); artwork.iconFile = name
        XCTAssertTrue(fixture.library.setArtwork(artwork, for: other.id))
        let found = try fixture.library.appIcon(for: "0100AAAA00000000", basePath: "/games/shared.nsp")
        XCTAssertEqual(found, dir.appendingPathComponent(name).path, "building Other must use Other's icon")
    }

    // The user sees: after the tab opens, the keyboard focus ring sits on the (empty) eShop tile while their own icon is the chosen one.
    func testCursorStaysOnTheChosenTileWhenTheEshopTileAppears() async throws {
        fixture = try ArtworkFixture()
        let first = fixture.editor(slot: .icon)
        await first.importFile(try fixture.chosenImage(width: 1200))
        XCTAssertTrue(first.save(to: fixture.library))
        var env = fixture.environment()
        env.media = { _, _ in .loaded(ArtworkStore.Media(screenshots: [], icon: "icon")) }
        let editor = ArtworkEditor(game: fixture.game, slot: .icon, artworkDirectory: fixture.artwork, env: env, labels: { L10n.string($0, .en) })
        XCTAssertEqual(editor.cursor, 0)
        await editor.load()
        let cursor = try XCTUnwrap(editor.cursor)
        XCTAssertTrue(editor.tiles[cursor].isSelected, "cursor \(cursor) on \(editor.tiles[cursor].id), chosen is \(editor.tiles.first { $0.isSelected }?.id ?? "-")")
    }

    // The user sees: nothing at once, but the rendered PNG of an icon choice a newer version wrote stays referenced forever (never cleaned up).
    func testDecodingAnIconOfAnUnknownKindDropsItsPNGNameToo() throws {
        let unknown = try JSONDecoder().decode(GameArtwork.self, from: Data(#"{"icon":{"source":{"kind":"future"}},"iconFile":"abc.png"}"#.utf8))
        XCTAssertNil(unknown.icon)
        XCTAssertNil(unknown.iconFile, "an icon of an unknown kind leaves no orphan PNG name behind")
    }
}
