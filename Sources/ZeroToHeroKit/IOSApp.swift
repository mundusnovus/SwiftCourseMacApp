// The iPhone and iPad app: the same course and screens as the Mac, with exercises run on Asteria Learn's server
// (RemoteRunner), since iOS can't compile Swift itself. No account is needed; progress stays on the device.
#if os(iOS)
import SwiftUI

/// The app's one scene. The iOS app target's @main App just shows this.
public struct ZeroToHeroScene: Scene {
    @State private var model: AppModel

    public init() {
        _ = Fonts.registered
        guard let course = try? Course.load() else { fatalError("The course is missing from the app.") }
        let model = AppModel(course: course)
        model.runner = RemoteRunner(device: RemoteRunner.installID)
        model.runnerState = .ready("Your code runs on Asteria Learn's server, so running it needs an internet connection.")
        if let i = Screenshots.arguments.firstIndex(of: "-lesson"), Screenshots.arguments.indices.contains(i + 1) {
            model.selection = Screenshots.arguments[i + 1]
        }
        _model = State(initialValue: model)
    }

    public var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .commands { LessonCommands(model: model) }
    }
}

/// For the App Store's screenshots: with the launch argument -screenshots, code lessons run as soon as they open and
/// show the code; -lesson <id> opens a lesson.
enum Screenshots {
    static let arguments = ProcessInfo.processInfo.arguments
    static let on = arguments.contains("-screenshots")
}

/// Settings, from the sidebar's gear: code size, where code runs, and starting over.
struct IOSSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("editorFontSize") private var fontSize = 15.0
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Editor") {
                    Stepper(value: $fontSize, in: 11...24, step: 1) { Text("Code size: \(Int(fontSize)) pt") }
                }
                Section {
                    RunnerStatus()
                } header: {
                    Text("Running your code")
                } footer: {
                    Text("Your code and the lesson's tests are sent to Asteria Learn, which compiles and runs them, then forgets them. No account is needed.")
                }
                Section("Progress") {
                    Text("\(model.progress.count(in: model.course.lessons)) of \(model.course.lessons.count) lessons done")
                    Button("Start the course again…", role: .destructive) { confirmReset = true }
                }
                Section {
                    Link("Privacy policy", destination: URL(string: "https://learn.asteria.technology/privacy/")!)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                } footer: {
                    Text("Swift: Zero to Hero, by Asteria Technology.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm) { dismiss() } } }
            .confirmationDialog("Start the course again?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Forget my progress and code", role: .destructive) { model.progress.resetAll() }
            } message: {
                Text("Every finished lesson and all your code will be forgotten. This cannot be undone.")
            }
        }
    }
}
#endif
