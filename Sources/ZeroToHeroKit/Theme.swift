// The Asteria Technology look: teal and gold on ink, with parchment; Asteria Pixel for display type.
import SwiftUI
import CoreText

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    static let asSea = Color(hex: 0x1c8c9e)
    static let asSeaBright = Color(hex: 0x3bb3c3)
    static let asSeaDeep = Color(hex: 0x116674)
    static let asGold = Color(hex: 0xe9b04b)
    static let asGoldDeep = Color(hex: 0xa8761a)
    static let asInk = Color(hex: 0x0a1518)
    static let asNight = Color(hex: 0x12232a)
    static let asCoal = Color(hex: 0x1a3038)
    static let asCream = Color(hex: 0xf4ecdb)
    static let asAlert = Color(hex: 0xc4432d)
    static let asPass = Color(hex: 0x4caf7a)

    /// The editor and console are always dark, like Xcode's default.
    static let editorBackground = Color(hex: 0x0e1b20)
    static let editorText = Color(hex: 0xdfe6ea)
}

extension Font {
    /// Asteria Pixel, the brand's display face, for titles. Falls back to a monospaced system font.
    static func display(_ size: CGFloat) -> Font {
        Fonts.registered ? .custom("Asteria Pixel", size: size) : .system(size: size, weight: .bold, design: .monospaced)
    }
}

enum Fonts {
    /// Registers Asteria Pixel from the app's resources, once.
    static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "AsteriaPixel-Regular", withExtension: "ttf")
                ?? Resources.url("AsteriaPixel-Regular.ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
}

/// Files that ship with the app: course.json and the font. In the built app they are in its Resources; when running
/// from the package during development, in the repository's Resources folder.
nonisolated enum Resources {
    static func url(_ name: String) -> URL? {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        if let url = Bundle.main.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil) { return url }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Resources/" + name).standardized
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}
