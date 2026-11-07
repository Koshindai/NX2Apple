import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import NXCore
import NXModel

/// Makes the same square crop the editor previews. Its bytes name the PNG, so a different crop repacks the app.
enum AppIconImage {
    static func render(_ file: URL, focus: ArtworkFocus, into directory: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096] as CFDictionary),
              let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ArtworkImport.Failure.unreadable }
        let side = CGFloat(min(image.width, image.height))
        let x = (CGFloat(image.width) - side) * min(max(focus.x, 0), 1)
        let y = (CGFloat(image.height) - side) * min(max(focus.y, 0), 1)
        guard let crop = image.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { throw ArtworkImport.Failure.unreadable }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        guard let square = context.makeImage() else { throw ArtworkImport.Failure.unreadable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ArtworkImport.Failure.unreadable }
        CGImageDestinationAddImage(destination, square, nil)
        guard CGImageDestinationFinalize(destination) else { throw ArtworkImport.Failure.unreadable }
        let name = SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined() + ".png"
        let output = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: output.path) { try (data as Data).write(to: output, options: .atomic) }
        return output
    }
}

extension GameLibrary {
    /// The game's own icon: the extraction's, else the icon of a Mac app built with it (one built with a custom icon shows that one).
    static func gameIcon(of game: LibraryGame) -> URL? {
        let output = game.outputDirectory.isEmpty ? game.sourceFolder : game.outputDirectory
        let extract = output + "/" + game.titleID.uppercased() + "_build/extract"
        if !output.isEmpty, let version = RomFSArchive.extractedVersion(in: extract) {
            let file = URL(fileURLWithPath: extract + "/" + version + "/icon.jpg")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        let built = URL(fileURLWithPath: game.appPath + "/Contents/Resources/AppIcon.icns")
        guard game.isReady, game.macAppIcon == nil, FileManager.default.fileExists(atPath: built.path) else { return nil }
        return built
    }

    func appIcon(for titleID: String, basePath: String) throws -> String? {
        let byTitle = games.first { $0.titleID.caseInsensitiveCompare(titleID) == .orderedSame }
        guard let game = byTitle ?? games.first(where: { !basePath.isEmpty && $0.inputs["base"]?.first == basePath }),
              game.artwork.icon != nil else { return nil }
        guard let name = game.artwork.iconFile, name == URL(fileURLWithPath: name).lastPathComponent, name != ".." else { throw ArtworkImport.Failure.unreadable }
        let file = ArtworkStore.customDirectory(for: game.id, in: artworkDirectory).appendingPathComponent(name)
        guard FileManager.default.isReadableFile(atPath: file.path) else { throw ArtworkImport.Failure.unreadable }
        return file.path
    }
}
