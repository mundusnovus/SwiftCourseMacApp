// The Mac app: one window with the course, a Lesson menu, and Settings. It compiles exercises with the Swift on this
// Mac, so nothing leaves the computer and it works offline.
#if os(macOS)
import SwiftUI

public enum ZeroToHero {
    /// Starts the Mac app, or with `--self-test`, checks the runner against every lesson and exits.
    public static func main() async {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--self-test") {
            exit(await SelfTest.run(solutionsPath: args.indices.contains(i + 1) ? args[i + 1] : nil))
        }
        ZeroToHeroMacApp.main()
    }
}

struct ZeroToHeroMacApp: App {
    @State private var model: AppModel

    init() {
        _ = Fonts.registered
        Smartz.configure(appName: "Swift: Zero to Hero", privacyURL: URL(string: "https://asteria.technology/privacy/")!)
        guard let course = try? Course.load() else { fatalError("The course is missing from the app.") }
        _model = State(initialValue: AppModel(course: course))
    }

    var body: some Scene {
        WindowGroup("Swift: Zero to Hero", id: "course") {
            RootView()
                .environment(model)
                .smartzPermission()
                .frame(minWidth: 980, minHeight: 640)
                .task { await findCompiler() }
                .onAppear { Screenshots.sizeWindow() }
        }
        .commands { LessonCommands(model: model) }

        Window("Smartz", id: "asteria") {
            AsteriaWindow()
        }
        .defaultSize(width: 520, height: 680)

        Settings {
            SettingsView().environment(model)
        }
    }

    func findCompiler() async {
        guard let toolchain = await Toolchain.find() else {
            model.runnerState = .unavailable("This Mac has no Swift compiler yet. The exercises need Apple's free Command Line Tools, or Xcode.")
            return
        }
        guard toolchain.isRecentEnough else {
            model.runnerState = .unavailable("This Mac has Swift \(toolchain.version). The exercises need Swift 6.2 or later: update Xcode or the Command Line Tools in Software Update.")
            return
        }
        model.runner = LocalRunner(toolchain: toolchain)
        model.runnerState = .ready(toolchain.hasEverything ? "Swift \(toolchain.version) on this Mac, ready to run your code."
                                                         : "Swift \(toolchain.version) on this Mac. The Swift 6.4 lessons need Swift 6.4: update when you can.")
    }
}

/// For the App Store's screenshots: with ZTH_SCREENSHOTS=1 the window opens at 1440 by 900 points and code lessons
/// run as soon as they open.
enum Screenshots {
    static let on = ProcessInfo.processInfo.environment["ZTH_SCREENSHOTS"] != nil
    static func sizeWindow() {
        guard on else { return }
        // ZTH_APPEARANCE=light or dark captures one appearance without changing the Mac's own setting.
        switch ProcessInfo.processInfo.environment["ZTH_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            window.setFrame(NSRect(x: 40, y: 40, width: 1440, height: 900), display: true)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("editorFontSize") private var fontSize = 14.0
    @State private var confirmReset = false

    var body: some View {
        // A stack, so the Smartz and account links (voice, what Smartz knows, the subscription) open in place.
        NavigationStack { form }
            .frame(width: 460, height: 620)
    }

    private var form: some View {
        Form {
            Section("Editor") {
                Slider(value: $fontSize, in: 11...24, step: 1) { Text("Code size: \(Int(fontSize)) pt") }
            }
            Section("Swift") {
                RunnerStatus()
            }
            AsteriaAccountSection { MacChats.smartz.forgetOnThisDevice() }
            SmartzSettingsSection()
            SmartzVoiceSection()
            SmartzLearningSection()
            Section("Progress") {
                Text("\(model.progress.count(in: model.course.lessons)) of \(model.course.lessons.count) lessons done")
                Button("Start the course again…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Start the course again?", isPresented: $confirmReset) {
            Button("Forget my progress and code", role: .destructive) { model.progress.resetAll() }
        } message: {
            Text("Every finished lesson and all your code will be forgotten. This cannot be undone.")
        }
    }
}
#endif
