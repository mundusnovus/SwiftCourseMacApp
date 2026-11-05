// Asteria 26: aqua on night, heavy for highlights, an aqua-violet-heavy gradient for Apple Intelligence.
// SF Pro for everything a person reads; Asteria Pixel only for the word "Asteria".
//
// RULE: tinted text keeps 4.5:1. Pure aqua on white is 1.3:1, so light appearance uses deep aqua #00826B (4.8:1);
// dark appearance uses pure aqua #00FFD3. Anything drawn ON an accent fill uses `onAccent`.
import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    /// A colour with a light-appearance value and a dark-appearance value.
    init(light: UInt32, dark: UInt32) {
        func components(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255)
        }
        let l = components(light), d = components(dark)
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }

    /// The accent: deep aqua #00826B in light, Asteria aqua #00FFD3 in dark.
    static let asSea = Color(light: 0x00826B, dark: 0x00FFD3)
    /// Asteria aqua, exactly.
    static let asSeaBright = Color(hex: 0x00FFD3)
    /// Deep aqua, for fills that carry white text.
    static let asSeaDeep = Color(hex: 0x00826B)
    /// Asteria heavy for highlights and small emphasis, at 4.5:1 in both appearances (#FF0058 itself is the fill).
    static let asGold = Color(light: 0xE0004E, dark: 0xFF3D7F)
    static let asHeavy = Color(hex: 0xFF0058)
    static let asViolet = Color(hex: 0x7A5CFF)
    /// Asteria night.
    static let asInk = Color(hex: 0x05080F)
    static let asNight = Color(hex: 0x0A1220)
    static let asCoal = Color(hex: 0x12202E)
    /// Starlight cream.
    static let asCream = Color(hex: 0xE9FBF7)
    static let asAlert = Color(light: 0xB23A26, dark: 0xFF9B85)
    static let asPass = Color(light: 0x2F7A3E, dark: 0x4CAF7A)
    /// Text and symbols on an accent fill: white on deep aqua, near-black on pure aqua.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x00140F)

    /// The editor and console are always dark, like Xcode's default, on Asteria night.
    static let editorBackground = Color(hex: 0x0A1220)
    static let editorText = Color(hex: 0xE9FBF7)
    static let consoleBackground = Color(hex: 0x05080F)
    static let consoleProblem = Color(hex: 0xFF9B85)
}

/// Apple Intelligence moments: aqua into violet into heavy.
nonisolated enum Brand {
    static let intelligence = LinearGradient(colors: [Color(hex: 0x00FFD3), Color(hex: 0x7A5CFF), Color(hex: 0xFF0058)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Font {
    /// Titles in SF Pro, bold. Scales with the text size setting where the system has one.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    /// Asteria Pixel, for the word "Asteria" and nothing else. Fixed size on purpose: it is a logo, not reading text.
    static func asteria(_ size: CGFloat) -> Font {
        Fonts.registered ? .custom("AsteriaPixel-Regular", fixedSize: size) : .system(size: size, weight: .semibold)
    }
}

extension Image {
    /// SF Symbols drawn the way the system draws them in toolbars and lists. Call before `.foregroundStyle`.
    func symbol() -> some View { symbolRenderingMode(.hierarchical) }
}

/// "Asteria" in Asteria Pixel and the product name in SF Pro.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.3) {
            Text("Asteria").font(.asteria(size))
            Text("Zero to Hero").font(.system(size: size * 0.82, weight: .semibold)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Asteria Zero to Hero")
        .accessibilityAddTraits(.isHeader)
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

/// The label of a prominent button sits on the accent fill, so it uses `onAccent`. On the Mac an inactive window draws
/// prominent buttons without the fill, and there the label goes back to the normal text colour.
struct OnAccentLabel: ViewModifier {
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    #else
    private let appearsActive = true
    #endif
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.foregroundStyle(appearsActive && isEnabled ? AnyShapeStyle(Color.onAccent) : AnyShapeStyle(.primary))
    }
}

extension View {
    func onAccentLabel() -> some View { modifier(OnAccentLabel()) }
}
