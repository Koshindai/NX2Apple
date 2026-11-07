import Combine
import XCTest
@testable import NX2Apple
@testable import NXCore
@testable import NXModel

@MainActor final class AppIconBuildTests: IsolatedDefaultsTestCase {
    func testOnlyStandaloneBuildsPassIconAndResetOmitsIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("icon-build-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, _ text: String = "") throws -> String {
            let file = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        }
        _ = try write(EngineLayout.marker)
        _ = try write(RepoLayout.romfsImageTool)
        _ = try write(RepoLayout.buildScript, "# '--work-dir' '--icon'\nimport sys\nsys.exit(7)\n")
        let base = try write("Game [0100000000001000].nsp")
        let keys = try write("prod.keys")
        let icon = try write("custom icon.png")
        let stores = LauncherStores(defaults: testDefaults)
        stores.repo.path = folder.path
        stores.dependencies.pythonPath = "/usr/bin/python3"
        stores.dependencies.dotnetPath = "/usr/bin/true"
        stores.dependencies.checked = true
        stores.dependencies.deps = [Dep(id: "test", name: "test", hint: "", present: true, installCmd: [])]
        let build = stores.build
        build.appReplaceCheck = { _ in true }
        build.cloudFolderCheck = { _ in false }
        build.slots[0].paths = [base]
        build.slots[3].paths = [keys]
        build.outDir = folder.path
        testDefaults.set(folder.appendingPathComponent("shell").path, forKey: "shellRoot")
        var chosen: String? = icon
        var lookups = 0
        build.appIcon = { title, path in
            XCTAssertEqual(title, "0100000000001000")
            XCTAssertEqual(path, base)
            lookups += 1
            return chosen
        }
        func run(target: String, oneGame: Bool, expectsIcon: Bool) {
            build.target = target
            stores.deviceStore.exportIPA = true
            stores.deviceStore.exportOneGame = oneGame
            build.startBuild()
            XCTAssertEqual(build.lastBuildCommand.contains("--icon"), expectsIcon, build.lastBuildCommand.joined(separator: " "))
            if expectsIcon, let index = build.lastBuildCommand.firstIndex(of: "--icon") { XCTAssertEqual(build.lastBuildCommand[index + 1], icon) }
            XCTAssertEqual(build.iconPassed, expectsIcon ? icon : nil, "what the library records as the built app's icon")
            if build.running {
                let ended = expectation(description: "stand-in exited")
                let token = build.$running.filter { !$0 }.prefix(1).sink { _ in ended.fulfill() }
                wait(for: [ended], timeout: 10)
                withExtendedLifetime(token) {}
            }
        }
        run(target: BuildTarget.mac, oneGame: false, expectsIcon: true)
        run(target: BuildTarget.ios, oneGame: true, expectsIcon: true)
        let before = lookups
        run(target: BuildTarget.ios, oneGame: false, expectsIcon: false)
        XCTAssertEqual(lookups, before, "shared app never reads a game's icon")
        chosen = nil
        run(target: BuildTarget.mac, oneGame: false, expectsIcon: false)
        chosen = icon
        _ = try write(RepoLayout.buildScript, "# '--work-dir'\nimport sys\nsys.exit(7)\n")   // an engine before --icon
        run(target: BuildTarget.mac, oneGame: false, expectsIcon: false)
    }
}
