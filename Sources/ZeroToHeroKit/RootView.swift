// The main window: the course in a sidebar, and the lesson (or the course's home) beside it.
import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model
    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            CourseSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 380)
        } detail: {
            Group {
                if let lesson = model.selectedLesson {
                    LessonView(lesson: lesson).id(lesson.id)
                } else {
                    HomeView()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Previous lesson", systemImage: "chevron.left") { model.go(by: -1) }
                        .disabled(model.selectedLesson.map { model.course.neighbours(of: $0.id).previous == nil } ?? true)
                    Button("Next lesson", systemImage: "chevron.right") { model.go(by: 1) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice).fontWeight(.semibold).padding(.horizontal, 18).padding(.vertical, 10)
                    .glassEffect().padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.notice)
        .tint(Color.asSea)
    }
}

struct CourseSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []
    @State private var showSettings = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Button { model.open(nil) } label: {
                Label { Text("Swift: Zero to Hero") } icon: { Image(systemName: "house").foregroundStyle(Color.asSea) }
            }
            .buttonStyle(.plain)
            ForEach(Array(model.course.chapters.enumerated()), id: \.offset) { ci, chapter in
                Section {
                    ForEach(chapter.modules) { module in
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(module.id) },
                                                            set: { open in if open { expanded.insert(module.id) } else { expanded.remove(module.id) } })) {
                            ForEach(module.lessons) { lesson in
                                LessonRow(lesson: lesson).tag(lesson.id)
                            }
                        } label: {
                            HStack {
                                Text(module.title)
                                Spacer()
                                Text("\(model.progress.count(in: module.lessons))/\(module.lessons.count)")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("\(ci + 1). \(chapter.title)")
                }
            }
        }
        .listStyle(.sidebar)
        #if os(iOS)
        .navigationTitle("Zero to Hero")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
        }
        .sheet(isPresented: $showSettings) { IOSSettingsView() }
        #endif
        .onAppear { if let id = model.selection, let m = model.course.module(of: id) { expanded.insert(m.module.id) } }
        .onChange(of: model.selection) { _, id in
            if let id, let m = model.course.module(of: id) { expanded.insert(m.module.id) }
        }
    }
}

struct LessonRow: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.progress.isDone(lesson.id) ? "checkmark.circle.fill" : icon)
                .foregroundStyle(model.progress.isDone(lesson.id) ? Color.asSea : .secondary)
                .frame(width: 18)
            Text(lesson.title).lineLimit(2)
        }
        .accessibilityValue(model.progress.isDone(lesson.id) ? "Done" : "")
    }
    var icon: String {
        switch lesson.type {
        case .quiz: "questionmark.circle"
        case .xcode: "hammer"
        case .project: "star"
        case .lab: "flask"
        case .workshop: "wrench.and.screwdriver"
        case .lesson: lesson.hasCode ? "chevron.left.forwardslash.chevron.right" : "book"
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = model.course.lessons, done = model.progress.count(in: all)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(model.course.versions.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.asGold)
                Text("Swift: Zero to Hero").font(.display(56)).fixedSize(horizontal: false, vertical: true)
                Text(model.course.subtitle).font(.title3).foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(all.count)) {
                    Text(done == 0 ? "\(all.count) lessons in nine chapters" : "\(done) of \(all.count) lessons done")
                }
                .tint(Color.asSea)
                .frame(maxWidth: 420)
                HStack(spacing: 12) {
                    if let next = model.nextLesson {
                        Button(done == 0 ? "Start the course" : "Continue: \(next.title)") { model.open(next) }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    } else {
                        Label("You finished the course. Well done.", systemImage: "star.fill").foregroundStyle(Color.asGold)
                    }
                }
                RunnerStatus()
                Divider().padding(.vertical, 6)
                Text(markdown(model.course.summary)).font(.body).foregroundStyle(.secondary).frame(maxWidth: 640, alignment: .leading)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                    ForEach(Array(model.course.chapters.enumerated()), id: \.offset) { i, chapter in
                        let lessons = chapter.modules.flatMap(\.lessons)
                        GridRow {
                            Text(String(format: "%02d", i + 1)).font(.display(22)).foregroundStyle(Color.asGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title).font(.headline)
                                Text(chapter.summary).font(.callout).foregroundStyle(.secondary)
                            }
                            Text("\(model.progress.count(in: lessons))/\(lessons.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Made by Asteria Technology. Open source.").font(.footnote).foregroundStyle(.tertiary).padding(.top, 12)
            }
            .padding(40)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Whether exercises can run, and what to do if not.
struct RunnerStatus: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.runnerState {
        case .looking:
            Label("Looking for the Swift compiler…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .ready(let what):
            Label(what, systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .unavailable(let why):
            VStack(alignment: .leading, spacing: 10) {
                Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(Color.asAlert)
                #if os(macOS)
                if Toolchain.inSandbox {
                    Button("Get Xcode from the App Store") { InstallTools.openXcode() }.buttonStyle(.glass)
                    Text("Xcode is free. When it is installed, open it once, then quit and reopen this app.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Install the Command Line Tools") { InstallTools.start() }.buttonStyle(.glass)
                    Text("Apple's free installer opens. When it finishes, quit and reopen this app. Xcode works too.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                #endif
            }
            .padding(16)
            .background(Color.asAlert.opacity(0.08), in: .rect(cornerRadius: 14))
        }
    }
}

#if os(macOS)
enum InstallTools {
    static func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        try? p.run()
    }
    static func openXcode() {
        NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")!)
    }
}
#endif
