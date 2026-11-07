import SwiftUI

/// Independent artwork for the library hero, cards and console covers, and the standalone app icon.
enum ArtworkSlot: String, CaseIterable, Codable {
    case hero, thumbnail, icon
}

/// Where in the image the crop keeps, 0...1 on each axis (CSS `object-position`). Centred by default.
struct ArtworkFocus: Codable, Equatable, Hashable {
    var x = 0.5
    var y = 0.5

    static let center = ArtworkFocus()
    var point: UnitPoint { UnitPoint(x: x, y: y) }

    init(x: Double = 0.5, y: Double = 0.5) { self.x = x; self.y = y }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
    }
}

/// An image for a slot and the focus point of its crop.
struct ArtworkChoice: Codable, Equatable, Hashable {
    /// Written by hand, as `{"kind":"screenshot","index":2}`: a renamed case or a reordered one must not change the file.
    enum Source: Codable, Equatable, Hashable {
        case banner
        case gameIcon, eshopIcon
        case screenshot(Int)
        /// A file name in the game's own folder (ArtworkStore.customDirectory), never a path.
        case imported(String)

        private enum CodingKeys: String, CodingKey { case kind, index, file }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "banner": self = .banner
            case "gameIcon": self = .gameIcon
            case "eshopIcon": self = .eshopIcon
            case "screenshot": self = .screenshot(try c.decode(Int.self, forKey: .index))
            case "imported": self = .imported(try c.decode(String.self, forKey: .file))
            case let kind: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown artwork source \(kind)")
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .gameIcon: try c.encode("gameIcon", forKey: .kind)
            case .eshopIcon: try c.encode("eshopIcon", forKey: .kind)
            case .banner: try c.encode("banner", forKey: .kind)
            case .screenshot(let index): try c.encode("screenshot", forKey: .kind); try c.encode(index, forKey: .index)
            case .imported(let file): try c.encode("imported", forKey: .kind); try c.encode(file, forKey: .file)
            }
        }
    }

    var source: Source
    var focus = ArtworkFocus.center

    init(source: Source, focus: ArtworkFocus = .center) { self.source = source; self.focus = focus }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(Source.self, forKey: .source)
        focus = try c.decodeIfPresent(ArtworkFocus.self, forKey: .focus) ?? .center
    }
}

/// What the player chose for each slot. nil is the default, and a thumbnail without a choice follows the hero.
struct GameArtwork: Codable, Equatable, Hashable {
    var hero: ArtworkChoice?
    var thumbnail: ArtworkChoice?
    var icon: ArtworkChoice?
    /// The rendered square PNG, kept beside imported source images.
    var iconFile: String?

    init(hero: ArtworkChoice? = nil, thumbnail: ArtworkChoice? = nil, icon: ArtworkChoice? = nil) {
        self.hero = hero; self.thumbnail = thumbnail; self.icon = icon
    }

    /// An unknown slot or source uses the default instead of preventing the library from loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hero = (try? c.decodeIfPresent(ArtworkChoice.self, forKey: .hero)) ?? nil
        thumbnail = (try? c.decodeIfPresent(ArtworkChoice.self, forKey: .thumbnail)) ?? nil
        if hero?.source == .gameIcon || hero?.source == .eshopIcon { hero = nil }
        if thumbnail?.source == .gameIcon || thumbnail?.source == .eshopIcon { thumbnail = nil }
        icon = try? c.decodeIfPresent(ArtworkChoice.self, forKey: .icon)
        iconFile = try? c.decodeIfPresent(String.self, forKey: .iconFile)
        if icon?.source == .gameIcon { icon = nil; iconFile = nil }
    }

    /// The choice the slot is drawn from: a thumbnail's own, else the hero's.
    func choice(for slot: ArtworkSlot) -> ArtworkChoice? {
        switch slot {
        case .icon: return icon
        case .hero: return hero
        case .thumbnail: return thumbnail ?? hero
        }
    }

    func focus(for slot: ArtworkSlot) -> UnitPoint { (choice(for: slot)?.focus ?? .center).point }

    var importedFiles: Set<String> {
        Set(([iconFile].compactMap { $0 }) + [hero, thumbnail, icon].compactMap { if case .imported(let file)? = $0?.source { return file } else { return nil } })
    }
}
